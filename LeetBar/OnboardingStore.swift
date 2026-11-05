import Combine
import Foundation

enum OnboardingStep: String, CaseIterable {
    case welcome, signIn, credentials, preferences, ready, complete

    var number: Int {
        switch self {
        case .welcome: 1
        case .signIn: 2
        case .credentials: 3
        case .preferences: 4
        case .ready, .complete: 5
        }
    }
}

@MainActor
final class OnboardingStore: ObservableObject {
    static let stepKey = "onboardingStep"
    @Published private(set) var step: OnboardingStep
    @Published private(set) var isPrepared = false
    @Published private(set) var isConnecting = false
    @Published private(set) var errorMessage: String?
    @Published var sessionCookie = "" { didSet { errorMessage = nil } }
    @Published var csrfToken = "" { didSet { errorMessage = nil } }

    private let defaults: UserDefaults
    private let account: AccountStore
    private let logger: DiagnosticLogger

    init(account: AccountStore, defaults: UserDefaults = .standard, logger: DiagnosticLogger = .disabled) {
        self.account = account
        self.defaults = defaults
        self.logger = logger
        step = defaults.string(forKey: Self.stepKey).flatMap(OnboardingStep.init(rawValue:)) ?? .welcome
    }

    var isComplete: Bool { step == .complete }

    func prepare() {
        guard !isPrepared else { return }
        account.restore()
        if defaults.object(forKey: Self.stepKey) == nil && account.hasSavedSession {
            // Existing installations keep their ordinary Settings experience.
            move(to: .complete)
        } else if (step == .preferences || step == .ready)
            && (!account.hasSavedSession || account.message != nil)
        {
            move(to: .credentials)
            errorMessage = account.message ?? "Please connect your LeetCode account to continue."
        }
        isPrepared = true
    }

    func advance() {
        guard !isConnecting else { return }
        switch step {
        case .welcome: move(to: .signIn)
        case .signIn: move(to: .credentials)
        case .preferences:
            guard requireSavedSession() else { return }
            move(to: .ready)
        default: break
        }
    }

    func goBack() {
        guard !isConnecting, !account.isWorking else { return }
        switch step {
        case .signIn: move(to: .welcome)
        case .credentials: move(to: .signIn)
        default: break
        }
    }

    func connect() async {
        guard step == .credentials, !isConnecting, !account.isWorking else { return }
        if let message = LeetCodeSession.validationMessage(sessionCookie: sessionCookie, csrfToken: csrfToken) {
            errorMessage = message
            logger.log(.warning, .invalidCredentials, reason: .invalidCookie)
            return
        }
        let candidate: LeetCodeSession
        do {
            candidate = try LeetCodeSession(sessionCookie: sessionCookie, csrfToken: csrfToken)
        } catch {
            logger.logFailure(.invalidCredentials, error: error)
            errorMessage = LeetCodeClient.message(for: error)
            return
        }
        guard let work = account.connect(candidate) else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        await work.value
        if account.connectionPhase == .connected {
            sessionCookie = ""
            csrfToken = ""
            move(to: .preferences)
        } else {
            errorMessage = account.message ?? "Connection was interrupted. Please try again."
        }
    }

    func finish() {
        guard step == .ready, requireSavedSession() else { return }
        sessionCookie = ""
        csrfToken = ""
        move(to: .complete)
    }

    func browserOpenFailed() {
        errorMessage = "Could not open your browser. Open https://leetcode.com/accounts/login/ manually."
        logger.log(.warning, .browserOpenFailed, reason: .system)
    }

    private func requireSavedSession() -> Bool {
        guard account.hasSavedSession, account.connectionPhase != .failed else {
            move(to: .credentials)
            errorMessage = "Please connect your LeetCode account to continue."
            return false
        }
        return true
    }

    private func move(to step: OnboardingStep) {
        errorMessage = nil
        self.step = step
        defaults.set(step.rawValue, forKey: Self.stepKey)
    }
}
