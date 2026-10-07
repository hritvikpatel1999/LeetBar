import Combine
import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var username: String?
    @Published private(set) var snapshot: LiveDashboard?
    @Published private(set) var hasSavedSession = false
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?

    private let storage: any SessionStoring
    private let client: any LeetCodeServing
    private var session: LeetCodeSession?
    private var didRestore = false
    private var generation = 0
    private var work: Task<Void, Never>?
    private var nextRefresh = Date.distantPast

    init(storage: any SessionStoring = KeychainSessionStore(), client: any LeetCodeServing = LeetCodeClient()) {
        self.storage = storage
        self.client = client
    }

    func restore() {
        guard !didRestore else { return }
        didRestore = true
        do {
            session = try storage.load()
            hasSavedSession = session != nil
        } catch {
            hasSavedSession = true
            message = LeetCodeClient.message(for: error)
        }
    }

    @discardableResult
    func connect(_ candidate: LeetCodeSession) -> Task<Void, Never>? {
        guard !isWorking else { return nil }
        return start { [self] ticket in
            do {
                let account = try await client.account(session: candidate)
                guard let username = account.username, !username.isEmpty else { throw LeetCodeError.signedOut }
                try Task.checkCancellation()
                guard generation == ticket else { return }
                try storage.save(candidate)
                session = candidate
                hasSavedSession = true
                didRestore = true
                self.username = username
                snapshot = nil
                nextRefresh = .now.addingTimeInterval(60)
                let result = try await client.dashboard(
                    session: candidate, username: username, now: .now, calendar: .current)
                try Task.checkCancellation()
                guard generation == ticket else { return }
                snapshot = result
            } catch {
                guard generation == ticket, !Task.isCancelled else { return }
                message = LeetCodeClient.message(for: error)
            }
        }
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard !isWorking, let session else { return nil }
        guard Date.now >= nextRefresh else {
            message = "Wait a minute before refreshing again."
            return nil
        }
        nextRefresh = .now.addingTimeInterval(60)
        return start { [self] ticket in
            do {
                let account = try await client.account(session: session)
                guard let username = account.username, !username.isEmpty else { throw LeetCodeError.signedOut }
                let result = try await client.dashboard(
                    session: session, username: username, now: .now, calendar: .current)
                try Task.checkCancellation()
                guard generation == ticket else { return }
                self.username = username
                snapshot = result
            } catch {
                guard generation == ticket, !Task.isCancelled else { return }
                if error as? LeetCodeError == .signedOut {
                    self.session = nil
                    username = nil
                    snapshot = nil
                }
                if error as? LeetCodeError == .rateLimited {
                    nextRefresh = .now.addingTimeInterval(300)
                }
                message = LeetCodeClient.message(for: error)
            }
        }
    }

    func refreshIfNeeded() {
        restore()
        if Date.now >= nextRefresh { refresh() }
    }

    func disconnect() {
        do {
            try storage.delete()
        } catch {
            message = LeetCodeClient.message(for: error)
            return
        }
        generation += 1
        work?.cancel()
        work = nil
        session = nil
        username = nil
        snapshot = nil
        hasSavedSession = false
        isWorking = false
        didRestore = true
        message = nil
        nextRefresh = .distantPast
    }

    private func start(_ operation: @escaping @MainActor (Int) async -> Void) -> Task<Void, Never> {
        generation += 1
        let ticket = generation
        isWorking = true
        message = nil
        let task = Task { @MainActor in
            await operation(ticket)
            if generation == ticket {
                isWorking = false
                work = nil
            }
        }
        work = task
        return task
    }
}
