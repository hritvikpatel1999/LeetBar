import Foundation
import OSLog

enum DiagnosticContext {
    @TaskLocal static var cycleID: UUID?
}

enum DiagnosticLevel: String, Codable, Sendable {
    case debug, info, warning, error

    var isProblem: Bool { self == .warning || self == .error }
}

enum DiagnosticEvent: String, Codable, Sendable {
    case startup, shutdown, sleep, wake, inactive, previousSessionUnclean, appReopened
    case verboseEnabled, verboseDisabled, logsCleared, logsEvicted, logsExportFailed, logsClearFailed, logsFolderFailed
    case sessionRestoreStarted, sessionRestored, sessionMissing, sessionRestoreFailed
    case sessionVerificationStarted, sessionVerified
    case connectionStarted, connectionVerified, connectionFailed, connectionCancelled
    case sessionSaveStarted, sessionSaved, sessionSaveFailed, sessionExpired, accountChanged
    case disconnectStarted, disconnected, disconnectFailed, invalidCredentials
    case refreshStarted, refreshFinished, refreshDeferred, refreshFailed
    case sectionSkipped, sectionFailed, sectionQueued, cacheCleared
    case requestStarted, requestFinished, requestFailed, requestCancelled
    case loginItemChangeStarted, loginItemChangeFinished, loginItemChangeFailed
    case browserOpenFailed, shortcutRegistrationFailed
}

enum DiagnosticOperation: String, Codable, Sendable {
    case account = "LeetBarAccount"
    case daily = "LeetBarDaily"
    case today = "LeetBarSubmissions"
    case contests = "LeetBarContests"
    case studyPlans = "LeetBarStudyPlans"
    case streak = "LeetBarStreak"
    case rating = "LeetBarContestRating"

    init(section: DashboardSection) {
        switch section {
        case .daily: self = .daily
        case .today: self = .today
        case .contests: self = .contests
        case .studyPlans: self = .studyPlans
        case .streak: self = .streak
        case .rating: self = .rating
        }
    }
}

enum DiagnosticReason: String, Codable, Sendable {
    case disabled, cacheFresh, completedDay, confirmedStreak, cooldown, rateLimited, busy, noSession
    case signedOut, blocked, network, timeout, cancelled, invalidResponse, decoding, graphQL, incompleteHistory
    case invalidCookie, keychain, invalidStoredSession, system, sizeLimit, retention

    static func forError(_ error: Error) -> DiagnosticReason {
        if error is CancellationError { return .cancelled }
        if let error = error as? LeetCodeError {
            switch error {
            case .signedOut: return .signedOut
            case .blocked: return .blocked
            case .rateLimited: return .rateLimited
            case .invalidResponse: return .invalidResponse
            case .incompleteHistory: return .incompleteHistory
            case .network: return .network
            }
        }
        if let error = error as? SessionStorageError {
            switch error {
            case .invalidCookie: return .invalidCookie
            case .keychain: return .keychain
            case .invalidStoredSession: return .invalidStoredSession
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return .timeout
            case .cancelled: return .cancelled
            default: return .network
            }
        }
        return .system
    }
}

struct DiagnosticRecord: Codable, Sendable {
    let timestamp: Date
    let sessionID: UUID
    let level: DiagnosticLevel
    let event: DiagnosticEvent
    var operation: DiagnosticOperation?
    var requestID: UUID?
    var cycleID: UUID?
    var reason: DiagnosticReason?
    var status: Int?
    var durationMilliseconds: Int?
    var responseBytes: Int?
    var page: Int?
    var count: Int?
    var systemCode: Int?
    var metadata: DiagnosticMetadata?
}

struct DiagnosticMetadata: Codable, Sendable {
    let version: String
    let build: String
    let macOS: String
    let architecture: String

    static var current: DiagnosticMetadata {
        #if arch(arm64)
            let architecture = "arm64"
        #else
            let architecture = "x86_64"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DiagnosticMetadata(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", architecture: architecture)
    }
}

enum DiagnosticStorageError: LocalizedError {
    case unavailable, unsafePath, exportFailed, entryTooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Logs could not be written. Check available disk space and permissions for Library/Logs/LeetBar."
        case .unsafePath: "The log location is not a regular local folder or file. Check Library/Logs/LeetBar."
        case .exportFailed: "Logs could not be exported. Choose a writable location with sufficient free space."
        case .entryTooLarge: "A diagnostic entry exceeded the log size limit and could not be written."
        }
    }
}

final class DiagnosticLogger: @unchecked Sendable {
    static let verboseKey = "verboseLoggingEnabled"
    static let shared = DiagnosticLogger(
        directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LeetBar"),
        verboseEnabled: UserDefaults.standard.bool(forKey: verboseKey))
    static let disabled = DiagnosticLogger(directory: nil)
    static let filenames = ["warnings-errors.log", "verbose.log"]

    let directory: URL?
    private let queue = DispatchQueue(label: "dev.leetbar.diagnostics", qos: .utility)
    private let sessionID = UUID()
    private let maxFileBytes: Int
    private let retention: TimeInterval
    private let clock: @Sendable () -> Date
    private var verboseEnabled: Bool
    private var failure: DiagnosticStorageError?
    private var maintenanceAt = Date.distantPast
    private var startupMetadata: DiagnosticMetadata?
    private let systemLogger = Logger(subsystem: "dev.leetbar.app", category: "diagnostics")

    init(
        directory: URL?, verboseEnabled: Bool = false, maxFileBytes: Int = 5 * 1024 * 1024,
        retention: TimeInterval = 7 * 24 * 3600, clock: @escaping @Sendable () -> Date = { .now }
    ) {
        precondition(maxFileBytes >= 2048 && retention > 0)
        self.directory = directory
        self.verboseEnabled = verboseEnabled
        self.maxFileBytes = maxFileBytes
        self.retention = retention
        self.clock = clock
    }

    var errorMessage: String? { queue.sync { failure?.localizedDescription } }
    var storedBytes: Int {
        queue.sync {
            guard let directory else { return 0 }
            return Self.filenames.reduce(0) { total, name in
                let size = try? directory.appendingPathComponent(name).resourceValues(forKeys: [.fileSizeKey]).fileSize
                return total + (size ?? 0)
            }
        }
    }

    func log(
        _ level: DiagnosticLevel, _ event: DiagnosticEvent, operation: DiagnosticOperation? = nil,
        requestID: UUID? = nil, cycleID: UUID? = nil, reason: DiagnosticReason? = nil,
        status: Int? = nil, durationMilliseconds: Int? = nil, responseBytes: Int? = nil,
        page: Int? = nil, count: Int? = nil, systemCode: Int? = nil
    ) {
        guard directory != nil else { return }
        let record = DiagnosticRecord(
            timestamp: clock(), sessionID: sessionID, level: level, event: event, operation: operation,
            requestID: requestID, cycleID: cycleID, reason: reason, status: status,
            durationMilliseconds: durationMilliseconds, responseBytes: responseBytes, page: page,
            count: count, systemCode: systemCode)
        queue.async { [self] in perform { try write(record) } }
    }

    func logFailure(_ event: DiagnosticEvent, error: Error, operation: DiagnosticOperation? = nil) {
        let reason = DiagnosticReason.forError(error)
        var code: Int?
        if case .keychain(let status) = error as? SessionStorageError { code = Int(status) }
        if let error = error as? URLError { code = error.code.rawValue }
        log(
            reason == .cancelled ? .info : .warning, event, operation: operation,
            cycleID: DiagnosticContext.cycleID, reason: reason, systemCode: code)
    }

    func start(metadata: DiagnosticMetadata = .current, previousSessionUnclean: Bool = false) {
        queue.async { [self] in
            startupMetadata = metadata
            perform {
                // Startup metadata is retained even when optional verbose event collection is off.
                try writeStartup()
                if previousSessionUnclean {
                    try write(
                        DiagnosticRecord(
                            timestamp: clock(), sessionID: sessionID, level: .warning, event: .previousSessionUnclean))
                }
            }
        }
    }

    func setVerboseEnabled(_ value: Bool) {
        queue.async { [self] in
            let wasEnabled = verboseEnabled
            // Opt-out takes effect even if writing the final verbose event fails.
            defer { verboseEnabled = value }
            perform {
                if !value && wasEnabled {
                    try write(
                        DiagnosticRecord(
                            timestamp: clock(), sessionID: sessionID, level: .info, event: .verboseDisabled))
                }
                verboseEnabled = value
                if value {
                    try writeStartup()
                    try write(
                        DiagnosticRecord(
                            timestamp: clock(), sessionID: sessionID, level: .info, event: .verboseEnabled))
                }
            }
        }
    }

    func flush() {
        // Every append is synchronized and closed; this barrier drains pending writes.
        queue.sync {}
    }

    func clear() throws {
        try queue.sync {
            do {
                try prepare()
                guard let directory else { return }
                for name in Self.filenames {
                    let url = directory.appendingPathComponent(name)
                    try requireRegularFile(url)
                    try Data().write(to: url, options: .atomic)
                    try protect(url)
                    try appendDirect(Data(), to: url)
                }
                failure = nil
                maintenanceAt = .distantPast
                try writeStartup()
                try write(DiagnosticRecord(timestamp: clock(), sessionID: sessionID, level: .info, event: .logsCleared))
            } catch {
                reportFailure(error)
                logFailure(.logsClearFailed, error: error)
                throw failure ?? DiagnosticStorageError.unavailable
            }
        }
    }

    func export(to destination: URL) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("LeetBar-logs-\(UUID())")
        defer {
            do {
                if FileManager.default.fileExists(atPath: temporary.path) {
                    try FileManager.default.removeItem(at: temporary)
                }
            } catch {
                systemLogger.error("Diagnostic export temporary-file cleanup failed.")
            }
        }
        do {
            try FileManager.default.createDirectory(
                at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let snapshot = temporary.appendingPathComponent("LeetBar-Logs")
            try FileManager.default.createDirectory(
                at: snapshot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try queue.sync {
                try prepare()
                try maintain(force: true)
                guard let directory else { throw DiagnosticStorageError.unavailable }
                for name in Self.filenames {
                    let source = directory.appendingPathComponent(name)
                    try requireRegularFile(source)
                    try FileManager.default.copyItem(at: source, to: snapshot.appendingPathComponent(name))
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(startupMetadata ?? .current).write(
                    to: snapshot.appendingPathComponent("diagnostic-summary.json"), options: .atomic)
            }
            let archive = temporary.appendingPathComponent("Logs.zip")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--keepParent", snapshot.path, archive.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw DiagnosticStorageError.exportFailed }
            try Data(contentsOf: archive).write(to: destination, options: .atomic)
            try protect(destination)
            try appendDirect(Data(), to: destination)
        } catch {
            systemLogger.error("Diagnostic export failed.")
            logFailure(.logsExportFailed, error: error)
            throw DiagnosticStorageError.exportFailed
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            reportFailure(error)
        }
    }

    private func reportFailure(_ error: Error) {
        failure = error as? DiagnosticStorageError ?? .unavailable
        // Do not log arbitrary errors: descriptions can contain paths or private data.
        systemLogger.error("Local diagnostic storage is unavailable. Check Diagnostics in LeetBar Settings.")
    }

    private func prepare() throws {
        guard let directory else { return }
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw DiagnosticStorageError.unsafePath
            }
        } else {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        for name in Self.filenames {
            let url = directory.appendingPathComponent(name)
            if !manager.fileExists(atPath: url.path) {
                guard manager.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o600])
                else { throw DiagnosticStorageError.unavailable }
            }
            try requireRegularFile(url)
            try protect(url)
        }
    }

    private func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw DiagnosticStorageError.unsafePath
        }
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func encode(_ record: DiagnosticRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0a)
        return data
    }

    private func writeStartup() throws {
        guard let startupMetadata else {
            try prepare()
            return
        }
        let record = DiagnosticRecord(
            timestamp: clock(), sessionID: sessionID, level: .info, event: .startup, metadata: startupMetadata)
        try write(record, startup: true)
    }

    private func write(_ record: DiagnosticRecord, startup: Bool = false) throws {
        guard directory != nil else { return }
        guard startup || record.level.isProblem || verboseEnabled else { return }
        try prepare()
        try maintain()
        let data = try encode(record)
        if startup || record.level.isProblem { try append(data, name: Self.filenames[0]) }
        if startup || verboseEnabled { try append(data, name: Self.filenames[1]) }
        failure = nil
    }

    private func maintain(force: Bool = false) throws {
        guard let directory, force || clock().timeIntervalSince(maintenanceAt) >= 3600 else { return }
        for name in Self.filenames {
            let url = directory.appendingPathComponent(name)
            if (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > maxFileBytes {
                try append(Data(), name: name)
            }
            let records = try Data(contentsOf: url).split(separator: 0x0a)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cutoff = clock().addingTimeInterval(-retention)
            let kept = records.filter { data in
                guard let record = try? decoder.decode(DiagnosticRecord.self, from: Data(data)) else { return false }
                return record.timestamp >= cutoff
            }
            if kept.count != records.count {
                var contents = Data()
                for record in kept {
                    contents.append(contentsOf: record)
                    contents.append(0x0a)
                }
                try contents.write(to: url, options: .atomic)
                try protect(url)
                try appendDirect(Data(), to: url)
                try evictionNotice(reason: .retention, count: records.count - kept.count)
            }
        }
        maintenanceAt = clock()
    }

    private func append(_ data: Data, name: String) throws {
        guard let directory else { return }
        let url = directory.appendingPathComponent(name)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard data.count <= maxFileBytes - 1024 else { throw DiagnosticStorageError.entryTooLarge }
        if size + data.count > maxFileBytes {
            let handle = try FileHandle(forReadingFrom: url)
            let contents: Data
            do {
                try handle.seek(toOffset: UInt64(max(0, size - maxFileBytes)))
                contents = try handle.read(upToCount: maxFileBytes) ?? Data()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            let records = contents.split(separator: 0x0a)
            var kept = Data()
            var keptCount = 0
            // Leave space for a non-recursive eviction warning and the triggering entry.
            let budget = max(0, maxFileBytes - data.count - 1024)
            let completeRecords = size > maxFileBytes ? records.dropFirst() : records[...]
            for record in completeRecords.reversed() {
                guard kept.count + record.count + 1 <= budget else { break }
                var line = Data(record)
                line.append(0x0a)
                kept.insert(contentsOf: line, at: 0)
                keptCount += 1
            }
            try kept.write(to: url, options: .atomic)
            try protect(url)
            let notice = DiagnosticRecord(
                timestamp: clock(), sessionID: sessionID, level: .warning, event: .logsEvicted,
                reason: .sizeLimit, count: size > maxFileBytes ? nil : records.count - keptCount)
            try appendDirect(try encode(notice), to: url)
            // Notices must reach the warnings file even when the verbose file was the one rotated.
            if name == Self.filenames[1] { try append(try encode(notice), name: Self.filenames[0]) }
        }
        try appendDirect(data, to: url)
    }

    private func evictionNotice(reason: DiagnosticReason, count: Int) throws {
        let data = try encode(
            DiagnosticRecord(
                timestamp: clock(), sessionID: sessionID, level: .warning, event: .logsEvicted, reason: reason,
                count: count))
        try append(data, name: Self.filenames[0])
        if verboseEnabled { try append(data, name: Self.filenames[1]) }
    }

    private func appendDirect(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }
}
