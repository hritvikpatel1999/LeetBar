import Foundation
import XCTest

final class DiagnosticsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LeetBarDiagnosticsTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testDefaultOffRoutesOnlyProblemsAndRetainsStartupMetadata() throws {
        let logger = DiagnosticLogger(directory: directory)
        logger.start()
        logger.log(.debug, .sectionSkipped, reason: .disabled)
        logger.log(.info, .requestStarted)
        logger.log(.warning, .sessionExpired)
        logger.log(.error, .sessionSaveFailed)
        logger.flush()
        let warnings = try records("warnings-errors.log")
        let verbose = try records("verbose.log")
        XCTAssertEqual(warnings.map(\.event), [.startup, .sessionExpired, .sessionSaveFailed])
        XCTAssertEqual(verbose.map(\.event), [.startup])
        XCTAssertNotNil(warnings.first?.metadata)
        XCTAssertNil(logger.errorMessage)
    }

    func testVerboseToggleIncludesProblemsAndStopsCollectingWhenDisabled() throws {
        let logger = DiagnosticLogger(directory: directory)
        logger.start()
        logger.setVerboseEnabled(true)
        logger.log(.info, .requestStarted)
        logger.log(.warning, .sessionExpired)
        logger.setVerboseEnabled(false)
        logger.log(.info, .requestFinished)
        logger.log(.error, .sessionSaveFailed)
        logger.flush()
        let verbose = try records("verbose.log")
        XCTAssertTrue(verbose.contains { $0.event == .requestStarted })
        XCTAssertTrue(verbose.contains { $0.event == .sessionExpired })
        XCTAssertTrue(verbose.contains { $0.event == .verboseDisabled })
        XCTAssertFalse(verbose.contains { $0.event == .requestFinished || $0.event == .sessionSaveFailed })
        XCTAssertTrue(try records("warnings-errors.log").contains { $0.event == .sessionSaveFailed })
    }

    func testConcurrentWritesAndFlushAreCompleteJSONLines() throws {
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true)
        DispatchQueue.concurrentPerform(iterations: 100) { value in
            logger.log(.warning, .requestFailed, count: value)
        }
        logger.flush()
        XCTAssertEqual(try records("warnings-errors.log").count, 100)
        XCTAssertEqual(try records("verbose.log").count, 100)
        XCTAssertEqual(Set(try records("verbose.log").compactMap(\.count)).count, 100)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
            DiagnosticLogger.filenames.sorted())
    }

    func testDiskLimitsEvictOldEntriesAndRecordNotices() throws {
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true, maxFileBytes: 2048)
        logger.start()
        for value in 0..<80 { logger.log(.warning, .requestFailed, count: value) }
        logger.flush()
        for name in DiagnosticLogger.filenames {
            XCTAssertLessThanOrEqual(try Data(contentsOf: directory.appendingPathComponent(name)).count, 2048)
            let entries = try records(name)
            XCTAssertTrue(entries.contains { $0.event == .logsEvicted && $0.reason == .sizeLimit })
            XCTAssertEqual(entries.last?.count, 79)
        }
        XCTAssertLessThanOrEqual(logger.storedBytes, 4096)
        XCTAssertNil(logger.errorMessage)
    }

    func testStartupTrimsPreexistingOversizedFileEvenWhenVerboseIsOff() throws {
        let first = DiagnosticLogger(directory: directory, verboseEnabled: true)
        for index in 0..<100 { first.log(.info, .requestStarted, count: index) }
        first.flush()
        let logger = DiagnosticLogger(directory: directory, maxFileBytes: 2048)
        logger.start()
        logger.flush()
        for name in DiagnosticLogger.filenames {
            XCTAssertLessThanOrEqual(try Data(contentsOf: directory.appendingPathComponent(name)).count, 2048)
            XCTAssertTrue(try records(name).contains { $0.event == .startup })
        }
        XCTAssertTrue(try records("warnings-errors.log").contains { $0.event == .logsEvicted })
    }

    @MainActor
    func testLifecycleDrainsLogsAndTracksCleanVersusUncleanSessions() throws {
        let suite = "LeetBarDiagnosticsTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true)
        let first = DiagnosticsAppDelegate(logger: logger, defaults: defaults)
        first.recordStartup()
        logger.log(.warning, .sessionExpired)
        let second = DiagnosticsAppDelegate(logger: logger, defaults: defaults)
        second.recordStartup()
        second.recordShutdown()
        let third = DiagnosticsAppDelegate(logger: logger, defaults: defaults)
        third.recordStartup()
        third.recordShutdown()
        let entries = try records("verbose.log")
        XCTAssertEqual(entries.filter { $0.event == .previousSessionUnclean }.count, 1)
        XCTAssertEqual(entries.last?.event, .shutdown)
        XCTAssertTrue(entries.contains { $0.event == .sessionExpired })
    }

    @MainActor
    func testExportErrorPersistsAcrossUIRefreshAndClearsOnSuccess() async throws {
        let suite = "LeetBarDiagnosticsTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let logger = DiagnosticLogger(directory: directory)
        let store = DiagnosticsStore(logger: logger, defaults: defaults)
        XCTAssertFalse(store.verboseEnabled)
        await store.export(to: directory.appendingPathComponent("missing-folder/export.zip"))
        XCTAssertNotNil(store.errorMessage)
        store.refresh()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isWorking)
        await store.export(to: directory.appendingPathComponent("success.zip"))
        XCTAssertNil(store.errorMessage)
        XCTAssertNotNil(store.statusMessage)
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(try records("warnings-errors.log").contains { $0.event == .logsExportFailed })
    }

    func testAgeRetentionEvictsAndRecordsNotice() throws {
        let clock = DiagnosticTestClock()
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true, retention: 3600, clock: { clock.now })
        logger.log(.warning, .sessionExpired)
        logger.flush()
        clock.advance(7200)
        logger.log(.warning, .requestFailed)
        logger.flush()
        for name in DiagnosticLogger.filenames {
            let entries = try records(name)
            XCTAssertFalse(entries.contains { $0.event == .sessionExpired })
            XCTAssertTrue(entries.contains { $0.event == .logsEvicted && $0.reason == .retention })
            XCTAssertTrue(entries.contains { $0.event == .requestFailed })
        }
    }

    func testClearDeletesOldDataAndReinitializesMetadata() throws {
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true)
        logger.start()
        logger.log(.warning, .sessionExpired)
        logger.flush()
        try logger.clear()
        XCTAssertEqual(try records("warnings-errors.log").map(\.event), [.startup])
        XCTAssertEqual(try records("verbose.log").map(\.event), [.startup, .logsCleared])
    }

    func testPreviousUncleanStopIsWarningWithoutVerboseEnabled() throws {
        let logger = DiagnosticLogger(directory: directory)
        logger.start(previousSessionUnclean: true)
        logger.log(.info, .shutdown)
        logger.flush()
        XCTAssertTrue(try records("warnings-errors.log").contains { $0.event == .previousSessionUnclean })
    }

    func testUnsafeLogFileFailsVisiblyWithoutChangingTarget() throws {
        let target = directory.appendingPathComponent("private-target")
        try Data("do not overwrite".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("warnings-errors.log"), withDestinationURL: target)
        let logger = DiagnosticLogger(directory: directory)
        logger.start()
        logger.flush()
        XCTAssertNotNil(logger.errorMessage)
        logger.log(.debug, .sectionSkipped)
        logger.flush()
        XCTAssertNotNil(logger.errorMessage)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "do not overwrite")
    }

    func testVerboseOptOutStillAppliesAfterStorageFailure() throws {
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true)
        logger.start()
        logger.flush()
        let file = directory.appendingPathComponent("verbose.log")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(
            at: file, withDestinationURL: directory.appendingPathComponent("warnings-errors.log"))
        logger.setVerboseEnabled(false)
        logger.flush()
        XCTAssertNotNil(logger.errorMessage)
        try FileManager.default.removeItem(at: file)
        try Data().write(to: file)
        logger.log(.info, .requestStarted)
        logger.log(.warning, .sessionExpired)
        logger.flush()
        XCTAssertTrue(try records("verbose.log").isEmpty)
        XCTAssertTrue(try records("warnings-errors.log").contains { $0.event == .sessionExpired })
        XCTAssertNil(logger.errorMessage)
    }

    func testUnwritableStorageAndExportFailExplicitly() throws {
        let file = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        let logger = DiagnosticLogger(directory: file)
        logger.log(.warning, .requestFailed)
        logger.flush()
        XCTAssertNotNil(logger.errorMessage)
        XCTAssertThrowsError(try logger.clear())
        XCTAssertThrowsError(try logger.export(to: directory.appendingPathComponent("export.zip")))
    }

    func testNetworkLogsOutcomesAndNeverRequestOrErrorSecrets() async throws {
        let secret = "SENSITIVE_SENTINEL_DO_NOT_LOG"
        let responses: [(Int, String)] = [
            (200, #"{"data":{"userStatus":{"isSignedIn":true,"username":"SENSITIVE_SENTINEL_DO_NOT_LOG"}}}"#),
            (429, secret),
            (200, #"{"errors":[{"message":"SENSITIVE_SENTINEL_DO_NOT_LOG"}]}"#),
            (200, secret),
            (200, #"{"data":{"userStatus":null},"errors":[{"message":"SENSITIVE_SENTINEL_DO_NOT_LOG"}]}"#),
        ]
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true)
        let client = LeetCodeClient(transport: MockLeetCodeTransport(responses: responses), logger: logger)
        let session = try LeetCodeSession(sessionCookie: secret, csrfToken: secret)
        for _ in responses {
            do { _ = try await client.account(session: session) } catch { XCTAssertTrue(error is LeetCodeError) }
        }
        logger.flush()
        let entries = try records("verbose.log")
        XCTAssertEqual(entries.filter { $0.event == .requestStarted }.count, responses.count)
        let completed = entries.filter { [.requestFinished, .requestFailed].contains($0.event) }
        XCTAssertEqual(completed.map(\.reason), [nil, .rateLimited, .graphQL, .decoding, .graphQL])
        XCTAssertTrue(completed.allSatisfy { $0.durationMilliseconds != nil && $0.responseBytes != nil })
        XCTAssertEqual(entries.filter { $0.event == .requestStarted }.map(\.requestID), completed.map(\.requestID))
        for name in DiagnosticLogger.filenames {
            XCTAssertFalse(
                try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8).contains(secret))
        }
    }

    func testTransportTimeoutAndCancellationHaveDistinctOutcomes() async throws {
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true)
        let session = try LeetCodeSession(sessionCookie: "test-session", csrfToken: "test-csrf")
        for code: URLError.Code in [.timedOut, .cancelled] {
            let client = LeetCodeClient(transport: FailingDiagnosticTransport(code: code), logger: logger)
            do {
                _ = try await client.account(session: session)
                XCTFail("Expected transport failure")
            } catch {
                XCTAssertEqual(error as? LeetCodeError, .network)
            }
        }
        logger.flush()
        let entries = try records("verbose.log")
        XCTAssertTrue(entries.contains { $0.reason == .timeout && $0.event == .requestFailed })
        XCTAssertTrue(entries.contains { $0.reason == .cancelled && $0.event == .requestCancelled })
        XCTAssertFalse(try records("warnings-errors.log").contains { $0.reason == .cancelled })
    }

    func testExportContainsBothSnapshotsAndNoPrivateErrorDescription() throws {
        let logger = DiagnosticLogger(directory: directory, verboseEnabled: true)
        logger.start()
        logger.logFailure(
            .connectionFailed,
            error: NSError(
                domain: "SENSITIVE_DOMAIN", code: 99,
                userInfo: [NSLocalizedDescriptionKey: "SENSITIVE_SENTINEL_DO_NOT_LOG"]))
        let archive = directory.appendingPathComponent("export.zip")
        try logger.export(to: archive)
        let extracted = directory.appendingPathComponent("extracted")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, extracted.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let snapshot = extracted.appendingPathComponent("LeetBar-Logs")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: snapshot.path).sorted(),
            ["diagnostic-summary.json", "verbose.log", "warnings-errors.log"])
        for name in try FileManager.default.contentsOfDirectory(atPath: snapshot.path) {
            let text = try String(contentsOf: snapshot.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(text.contains("SENSITIVE"))
            XCTAssertFalse(text.contains(NSHomeDirectory()))
        }
        let permissions = try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    private func records(_ name: String) throws -> [DiagnosticRecord] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try data.split(separator: 0x0a).map { try decoder.decode(DiagnosticRecord.self, from: Data($0)) }
    }
}

private final class DiagnosticTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
}

private struct FailingDiagnosticTransport: LeetCodeTransport {
    let code: URLError.Code
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(code)
    }
}
