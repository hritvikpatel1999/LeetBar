import AppKit
import Combine
import SwiftUI
import XCTest

@MainActor
final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var storage: OnboardingSessionStore!
    private var service: OnboardingService!
    private var account: AccountStore!
    private var onboarding: OnboardingStore!

    override func setUp() async throws {
        suite = "LeetBarOnboardingTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        storage = OnboardingSessionStore()
        service = OnboardingService()
        account = AccountStore(storage: storage, client: service)
        onboarding = OnboardingStore(account: account, defaults: defaults)
        onboarding.prepare()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        onboarding = nil
        account = nil
        defaults = nil
    }

    func testWelcomeAndSignInAdvanceOnlyOnExplicitActionAndPersist() {
        XCTAssertEqual(onboarding.step, .welcome)
        XCTAssertFalse(onboarding.isComplete)
        onboarding.advance()
        XCTAssertEqual(onboarding.step, .signIn)
        XCTAssertEqual(defaults.string(forKey: OnboardingStore.stepKey), "signIn")
        let resumed = OnboardingStore(account: account, defaults: defaults)
        resumed.prepare()
        XCTAssertEqual(resumed.step, .signIn)
        resumed.advance()
        XCTAssertEqual(resumed.step, .credentials)
        resumed.advance()
        XCTAssertEqual(resumed.step, .credentials)
    }

    func testDraftsSurviveWindowLifetimeButAreNotPersisted() {
        reachCredentials()
        onboarding.sessionCookie = "PRIVATE_SESSION_SENTINEL"
        onboarding.csrfToken = "PRIVATE_CSRF_SENTINEL"
        // Closing the window does not destroy its app-owned store.
        onboarding.prepare()
        XCTAssertEqual(onboarding.sessionCookie, "PRIVATE_SESSION_SENTINEL")
        let persisted = defaults.persistentDomain(forName: suite) ?? [:]
        XCTAssertEqual(Set(persisted.keys), [OnboardingStore.stepKey])
        XCTAssertFalse(String(describing: persisted).contains("PRIVATE"))
        let restarted = OnboardingStore(account: account, defaults: defaults)
        restarted.prepare()
        XCTAssertEqual(restarted.step, .credentials)
        XCTAssertTrue(restarted.sessionCookie.isEmpty)
        XCTAssertTrue(restarted.csrfToken.isEmpty)
    }

    func testInvalidCredentialsNeverReachNetworkOrStorage() async {
        reachCredentials()
        let cases = [
            ("", "csrf", "LEETCODE_SESSION"),
            ("session", "", "csrftoken"),
            ("LEETCODE_SESSION=private", "csrf", "without cookie names"),
            ("session", "csrftoken=private", "without cookie names"),
            ("Cookie: LEETCODE_SESSION=private; csrftoken=private", "csrf", "Cookie header"),
            ("session", "\"quoted\"", "unsupported"),
            ("line\nbreak", "csrf", "unsupported"),
            (String(repeating: "a", count: 16_385), "csrf", "too long"),
        ]
        for (session, csrf, expected) in cases {
            onboarding.sessionCookie = session
            onboarding.csrfToken = csrf
            await onboarding.connect()
            XCTAssertTrue(onboarding.errorMessage?.contains(expected) == true)
            XCTAssertFalse(onboarding.isConnecting)
            XCTAssertEqual(onboarding.step, .credentials)
        }
        let calls = await service.accountCalls
        XCTAssertEqual(calls, 0)
        XCTAssertNil(try? storage.load())
    }

    func testLocalValidationTrimsOuterWhitespaceAndDoesNotEchoSecrets() throws {
        let session = try LeetCodeSession(sessionCookie: "  sample-session\n", csrfToken: "\tsample-csrf ")
        XCTAssertEqual(session.sessionCookie, "sample-session")
        XCTAssertEqual(session.csrfToken, "sample-csrf")
        let error = LeetCodeSession.validationMessage(
            sessionCookie: "LEETCODE_SESSION=PRIVATE_SENTINEL", csrfToken: "sample")
        XCTAssertFalse(error?.contains("PRIVATE_SENTINEL") == true)
        XCTAssertThrowsError(try LeetCodeSession(sessionCookie: "LEETCODE_SESSION=sample", csrfToken: "csrf"))
    }

    func testConnectionPhasesAndSuccessfulResumeAtPreferences() async throws {
        reachCredentials()
        enterCredentials()
        var phases: [ConnectionPhase] = []
        let observer = account.$connectionPhase.sink { phases.append($0) }
        await onboarding.connect()
        withExtendedLifetime(observer) {}
        XCTAssertEqual(phases, [.idle, .verifying, .saving, .loading, .connected])
        XCTAssertEqual(onboarding.step, .preferences)
        XCTAssertTrue(account.hasSavedSession)
        XCTAssertTrue(onboarding.sessionCookie.isEmpty)
        XCTAssertTrue(onboarding.csrfToken.isEmpty)
        let restoredAccount = AccountStore(storage: storage, client: service)
        let resumed = OnboardingStore(account: restoredAccount, defaults: defaults)
        resumed.prepare()
        XCTAssertEqual(resumed.step, .preferences)
        resumed.advance()
        XCTAssertEqual(resumed.step, .ready)
        XCTAssertFalse(resumed.isComplete)
        XCTAssertEqual(defaults.string(forKey: OnboardingStore.stepKey), "ready")
        let readyAccount = AccountStore(storage: storage, client: service)
        let ready = OnboardingStore(account: readyAccount, defaults: defaults)
        ready.prepare()
        XCTAssertEqual(ready.step, .ready)
        XCTAssertFalse(ready.isComplete)
        ready.finish()
        XCTAssertTrue(ready.isComplete)
        let completed = OnboardingStore(account: restoredAccount, defaults: defaults)
        completed.prepare()
        XCTAssertTrue(completed.isComplete)
    }

    func testSignedOutAndKeychainFailuresStayOnCredentials() async {
        reachCredentials()
        enterCredentials()
        await service.setIdentityError(.signedOut)
        await onboarding.connect()
        XCTAssertEqual(onboarding.step, .credentials)
        XCTAssertEqual(account.connectionPhase, .failed)
        XCTAssertNotNil(onboarding.errorMessage)
        XCTAssertFalse(account.hasSavedSession)
        XCTAssertEqual(onboarding.sessionCookie, "sample-session")
        await service.setIdentityError(nil)
        storage.failSave = true
        await onboarding.connect()
        XCTAssertEqual(onboarding.step, .credentials)
        XCTAssertEqual(account.connectionPhase, .failed)
        XCTAssertTrue(onboarding.errorMessage?.contains("Keychain") == true)
        XCTAssertNil(account.username)
        XCTAssertFalse(account.hasSavedSession)
    }

    func testClosingDuringConnectionDoesNotCancelOrDuplicateWork() async {
        reachCredentials()
        enterCredentials()
        await service.pauseIdentity()
        let connecting = Task { await onboarding.connect() }
        await service.waitUntilStarted()
        XCTAssertTrue(onboarding.isConnecting)
        XCTAssertEqual(account.connectionPhase, .verifying)
        onboarding.prepare()
        onboarding.goBack()
        await onboarding.connect()
        XCTAssertEqual(onboarding.step, .credentials)
        let calls = await service.accountCalls
        XCTAssertEqual(calls, 1)
        await service.resumeIdentity()
        await connecting.value
        XCTAssertEqual(onboarding.step, .preferences)
        XCTAssertFalse(onboarding.isConnecting)
        XCTAssertEqual(defaults.string(forKey: OnboardingStore.stepKey), "preferences")
    }

    func testDisconnectDuringConnectionDoesNotAdvanceOnboarding() async {
        reachCredentials()
        enterCredentials()
        await service.pauseIdentity()
        let connecting = Task { await onboarding.connect() }
        await service.waitUntilStarted()
        account.disconnect()
        await service.resumeIdentity()
        await connecting.value
        XCTAssertEqual(onboarding.step, .credentials)
        XCTAssertNotNil(onboarding.errorMessage)
        XCTAssertFalse(account.hasSavedSession)
        XCTAssertNil(try? storage.load())
    }

    func testDashboardFailureDoesNotBecomeAnAuthenticationFailure() async {
        reachCredentials()
        enterCredentials()
        await service.setDashboardError(.rateLimited)
        await onboarding.connect()
        XCTAssertEqual(account.connectionPhase, .connected)
        XCTAssertEqual(onboarding.step, .preferences)
        XCTAssertNotNil(account.message)
        XCTAssertTrue(account.hasSavedSession)
    }

    func testSessionRejectedDuringDashboardLoadRequiresReconnect() async {
        reachCredentials()
        enterCredentials()
        await service.setDashboardError(.signedOut)
        await onboarding.connect()
        XCTAssertEqual(account.connectionPhase, .failed)
        XCTAssertEqual(onboarding.step, .credentials)
        XCTAssertNil(account.username)
        XCTAssertNotNil(onboarding.errorMessage)
    }

    func testExistingUsersAreNotForcedThroughFirstRunSetup() throws {
        try storage.save(LeetCodeSession(sessionCookie: "existing", csrfToken: "existing-csrf"))
        let existingAccount = AccountStore(storage: storage, client: service)
        let existing = OnboardingStore(account: existingAccount, defaults: defaults)
        existing.prepare()
        XCTAssertTrue(existing.isComplete)
        XCTAssertTrue(existingAccount.hasSavedSession)
    }

    func testMissingSavedSessionReturnsFromConnectedPagesToCredentials() {
        for step in [OnboardingStep.preferences, .ready] {
            defaults.set(step.rawValue, forKey: OnboardingStore.stepKey)
            let resumed = OnboardingStore(account: account, defaults: defaults)
            resumed.prepare()
            XCTAssertEqual(resumed.step, .credentials)
            XCTAssertNotNil(resumed.errorMessage)
        }
    }

    func testFinishCannotSkipConnection() {
        onboarding.finish()
        XCTAssertFalse(onboarding.isComplete)
        defaults.set("preferences", forKey: OnboardingStore.stepKey)
        let resumed = OnboardingStore(account: account, defaults: defaults)
        resumed.advance()
        XCTAssertEqual(resumed.step, .credentials)
        XCTAssertNotNil(resumed.errorMessage)
        defaults.set("ready", forKey: OnboardingStore.stepKey)
        let ready = OnboardingStore(account: account, defaults: defaults)
        ready.finish()
        XCTAssertEqual(ready.step, .credentials)
        XCTAssertNotNil(ready.errorMessage)
    }

    func testPreferencesCannotFinishWithoutShowingReadyPage() async {
        reachCredentials()
        enterCredentials()
        await onboarding.connect()
        onboarding.finish()
        XCTAssertEqual(onboarding.step, .preferences)
        onboarding.advance()
        XCTAssertEqual(onboarding.step, .ready)
        onboarding.advance()
        onboarding.goBack()
        XCTAssertEqual(onboarding.step, .ready)
        onboarding.finish()
        XCTAssertTrue(onboarding.isComplete)
    }

    func testDisconnectOnReadyPageRequiresReconnect() async {
        reachCredentials()
        enterCredentials()
        await onboarding.connect()
        onboarding.advance()
        account.disconnect()
        onboarding.finish()
        XCTAssertEqual(onboarding.step, .credentials)
        XCTAssertFalse(onboarding.isComplete)
        XCTAssertNotNil(onboarding.errorMessage)
    }

    func testBrowserFailureAndBackNavigationAreRecoverable() {
        onboarding.advance()
        onboarding.browserOpenFailed()
        XCTAssertNotNil(onboarding.errorMessage)
        onboarding.advance()
        XCTAssertNil(onboarding.errorMessage)
        onboarding.goBack()
        XCTAssertEqual(onboarding.step, .signIn)
        onboarding.goBack()
        XCTAssertEqual(onboarding.step, .welcome)
        onboarding.goBack()
        XCTAssertEqual(onboarding.step, .welcome)
    }

    func testWindowContentHasSettingsDimensionsOnEveryPage() {
        for step in OnboardingStep.allCases where step != .complete {
            defaults.set(step.rawValue, forKey: OnboardingStore.stepKey)
            let model = OnboardingStore(account: account, defaults: defaults)
            let view = OnboardingView(
                onboarding: model, account: account, showStreak: .constant(true),
                showQuickLinks: .constant(true), showUpcomingContests: .constant(true),
                showTodaySection: .constant(true), showStudyPlans: .constant(true))
            let host = NSHostingView(rootView: view)
            XCTAssertEqual(host.fittingSize, NSSize(width: 500, height: 500), step.rawValue)
        }
    }

    private func reachCredentials() {
        onboarding.advance()
        onboarding.advance()
    }

    private func enterCredentials() {
        onboarding.sessionCookie = "sample-session"
        onboarding.csrfToken = "sample-csrf"
    }
}

private final class OnboardingSessionStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: LeetCodeSession?
    var failSave = false

    func load() throws -> LeetCodeSession? { lock.withLock { value } }
    func save(_ session: LeetCodeSession) throws {
        if failSave { throw SessionStorageError.keychain(-1) }
        lock.withLock { value = session }
    }
    func delete() throws { lock.withLock { value = nil } }
}

private actor OnboardingService: LeetCodeServing {
    private var identityError: LeetCodeError?
    private var dashboardError: LeetCodeError?
    private(set) var accountCalls = 0
    private var shouldPauseIdentity = false
    private var identityContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func setIdentityError(_ error: LeetCodeError?) { identityError = error }
    func setDashboardError(_ error: LeetCodeError?) { dashboardError = error }
    func pauseIdentity() { shouldPauseIdentity = true }
    func waitUntilStarted() async {
        if identityContinuation != nil { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func resumeIdentity() {
        shouldPauseIdentity = false
        identityContinuation?.resume()
        identityContinuation = nil
    }

    func account(session: LeetCodeSession) async throws -> LeetCodeAccount {
        accountCalls += 1
        if shouldPauseIdentity {
            await withCheckedContinuation {
                identityContinuation = $0
                startedContinuation?.resume()
                startedContinuation = nil
            }
        }
        if let identityError { throw identityError }
        return LeetCodeAccount(isSignedIn: true, username: "test-user")
    }

    func dashboard(
        session: LeetCodeSession, username: String, now: Date, calendar: Calendar,
        sections: Set<DashboardSection>
    ) async throws -> LiveDashboard {
        if let dashboardError { throw dashboardError }
        return LiveDashboard(
            daily: nil, stats: nil, contests: [], studyPlans: [], streak: nil, contestRating: nil,
            checkedAt: now, sectionIssues: [:])
    }
}
