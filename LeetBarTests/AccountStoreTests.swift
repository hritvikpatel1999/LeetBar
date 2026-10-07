import XCTest

@MainActor
final class AccountStoreTests: XCTestCase {
    func testValidSessionIsSavedAndDisconnectClearsState() async throws {
        let storage = TestSessionStore()
        let account = AccountStore(storage: storage, client: TestLeetCodeService())
        let candidate = try LeetCodeSession(sessionCookie: "test-session", csrfToken: "test-csrf")
        let work = account.connect(candidate)
        await work?.value
        XCTAssertEqual(try storage.load(), candidate)
        XCTAssertEqual(account.username, "example")
        XCTAssertNotNil(account.snapshot)
        XCTAssertEqual(account.snapshot?.contestRating, .rated(1641.6))
        account.disconnect()
        XCTAssertNil(try storage.load())
        XCTAssertNil(account.username)
        XCTAssertNil(account.snapshot)
        XCTAssertFalse(account.hasSavedSession)
    }

    func testFailedValidationDoesNotOverwriteSavedSession() async throws {
        let storage = TestSessionStore()
        let original = try LeetCodeSession(sessionCookie: "original", csrfToken: "original-csrf")
        try storage.save(original)
        let account = AccountStore(storage: storage, client: TestLeetCodeService(identityError: .signedOut))
        account.restore()
        let candidate = try LeetCodeSession(sessionCookie: "invalid", csrfToken: "test-csrf")
        let work = account.connect(candidate)
        await work?.value
        XCTAssertEqual(try storage.load(), original)
        XCTAssertNotNil(account.message)
    }

    func testRefreshLoadsRatingForTheRestoredAccount() async throws {
        let storage = TestSessionStore()
        try storage.save(LeetCodeSession(sessionCookie: "test-session", csrfToken: "test-csrf"))
        let account = AccountStore(storage: storage, client: TestLeetCodeService())
        account.restore()
        await account.refresh()?.value
        XCTAssertEqual(account.username, "example")
        XCTAssertEqual(account.snapshot?.contestRating, .rated(1641.6))
    }

    func testKeychainFailureDoesNotReportConnected() async throws {
        let storage = TestSessionStore(failSave: true)
        let account = AccountStore(storage: storage, client: TestLeetCodeService())
        let work = account.connect(try LeetCodeSession(sessionCookie: "test-session", csrfToken: "test-csrf"))
        await work?.value
        XCTAssertFalse(account.hasSavedSession)
        XCTAssertNil(account.username)
        XCTAssertNil(account.snapshot)
        XCTAssertNotNil(account.message)
    }

    func testDisconnectPreventsAnInflightConnectionFromSaving() async throws {
        let storage = TestSessionStore()
        let service = PausedLeetCodeService()
        let account = AccountStore(storage: storage, client: service)
        let work = account.connect(try LeetCodeSession(sessionCookie: "test-session", csrfToken: "test-csrf"))
        await service.waitUntilStarted()
        account.disconnect()
        await service.complete()
        await work?.value
        XCTAssertNil(try storage.load())
        XCTAssertNil(account.username)
        XCTAssertFalse(account.hasSavedSession)
        XCTAssertFalse(account.isWorking)
    }
}

private final class TestSessionStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: LeetCodeSession?
    private let failSave: Bool

    init(failSave: Bool = false) { self.failSave = failSave }
    func load() throws -> LeetCodeSession? { lock.withLock { value } }
    func save(_ session: LeetCodeSession) throws {
        if failSave { throw SessionStorageError.keychain(-1) }
        lock.withLock { value = session }
    }
    func delete() throws { lock.withLock { value = nil } }
}

private struct TestLeetCodeService: LeetCodeServing {
    var identityError: LeetCodeError?
    func account(session: LeetCodeSession) async throws -> LeetCodeAccount {
        if let identityError { throw identityError }
        return LeetCodeAccount(isSignedIn: true, username: "example")
    }
    func dashboard(session: LeetCodeSession, username: String, now: Date, calendar: Calendar) async throws
        -> LiveDashboard
    {
        guard username == "example" else { throw LeetCodeError.invalidResponse }
        return LiveDashboard(
            daily: nil, stats: DailyStats(submissions: 0, problemsSolved: 0), contests: [], streak: nil,
            contestRating: .rated(1641.6), checkedAt: now,
            issues: [])
    }
}

private actor PausedLeetCodeService: LeetCodeServing {
    private var continuation: CheckedContinuation<LeetCodeAccount, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func account(session: LeetCodeSession) async throws -> LeetCodeAccount {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func complete() {
        continuation?.resume(returning: LeetCodeAccount(isSignedIn: true, username: "example"))
        continuation = nil
    }
    func dashboard(session: LeetCodeSession, username: String, now: Date, calendar: Calendar) async throws
        -> LiveDashboard
    {
        throw LeetCodeError.invalidResponse
    }
}
