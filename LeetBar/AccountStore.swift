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
    private let now: () -> Date
    private var preferences: DashboardPreferences
    private var fetchedAt: [DashboardSection: Date] = [:]
    private var retryAfter: [DashboardSection: Date] = [:]
    private var pendingSections: Set<DashboardSection> = []
    private var rateLimitedUntil = Date.distantPast
    private var streakBaseline: (day: DateInterval, count: Int)?
    private var confirmedStreakDay: DateInterval?

    init(
        storage: any SessionStoring = KeychainSessionStore(), client: any LeetCodeServing = LeetCodeClient(),
        preferences: DashboardPreferences = DashboardPreferences(), now: @escaping () -> Date = { .now }
    ) {
        self.storage = storage
        self.client = client
        self.preferences = preferences
        self.now = now
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
                clearDashboardCache()
                rateLimitedUntil = .distantPast
                nextRefresh = now().addingTimeInterval(60)
                try await load(session: candidate, username: username, sections: preferences.sections, ticket: ticket)
            } catch {
                guard generation == ticket, !Task.isCancelled else { return }
                if error as? LeetCodeError == .rateLimited {
                    nextRefresh = now().addingTimeInterval(300)
                    rateLimitedUntil = nextRefresh
                    pendingSections = []
                }
                message = LeetCodeClient.message(for: error)
            }
        }
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard !isWorking, let session else { return nil }
        guard now() >= nextRefresh else {
            message = "Wait a minute before refreshing again."
            return nil
        }
        nextRefresh = now().addingTimeInterval(60)
        return refresh(session: session, sections: dueSections(preferences.sections))
    }

    private func refresh(session: LeetCodeSession, sections: Set<DashboardSection>) -> Task<Void, Never>? {
        guard !sections.isEmpty else { return nil }
        return start { [self] ticket in
            do {
                let account = try await client.account(session: session)
                guard let username = account.username, !username.isEmpty else { throw LeetCodeError.signedOut }
                try Task.checkCancellation()
                guard generation == ticket else { return }
                if self.username != nil && self.username != username {
                    clearDashboardCache()
                }
                try await load(
                    session: session, username: username,
                    sections: self.username != nil && self.username != username ? preferences.sections : sections,
                    ticket: ticket)
                self.username = username
            } catch {
                guard generation == ticket, !Task.isCancelled else { return }
                if error as? LeetCodeError == .signedOut {
                    self.session = nil
                    username = nil
                    clearDashboardCache()
                    pendingSections = []
                }
                if error as? LeetCodeError == .rateLimited {
                    nextRefresh = now().addingTimeInterval(300)
                    rateLimitedUntil = nextRefresh
                    pendingSections = []
                }
                message = LeetCodeClient.message(for: error)
            }
        }
    }

    func refreshIfNeeded() {
        restore()
        if now() >= nextRefresh { refresh() }
    }

    @discardableResult
    func updatePreferences(_ value: DashboardPreferences) -> Task<Void, Never>? {
        let enabled = value.sections.subtracting(preferences.sections)
        preferences = value
        pendingSections.formUnion(enabled)
        pendingSections.formIntersection(value.sections)
        return refreshPendingSections()
    }

    private func dueSections(_ sections: Set<DashboardSection>) -> Set<DashboardSection> {
        let date = now()
        let completedDay = completedChallengeDay(at: date)
        return sections.filter { section in
            if section == .daily, completedDay != nil { return false }
            if section == .streak, let completedDay, confirmedStreakDay == completedDay { return false }
            if let retry = retryAfter[section], date < retry { return false }
            guard let fetched = fetchedAt[section] else { return true }
            if [.daily, .today, .streak].contains(section),
                !Calendar.current.isDate(fetched, inSameDayAs: date)
            {
                return true
            }
            return date.timeIntervalSince(fetched) >= section.refreshInterval
        }
    }

    private func completedChallengeDay(at date: Date) -> DateInterval? {
        guard let daily = snapshot?.daily, daily.isCompleted == true,
            let day = daily.dayInterval, date >= day.start, date < day.end
        else { return nil }
        return day
    }

    private func updateStreakConfirmation(_ result: LiveDashboard, sections: Set<DashboardSection>, startedAt: Date) {
        guard let daily = snapshot?.daily, let day = daily.dayInterval,
            startedAt >= day.start, startedAt < day.end, now() >= day.start, now() < day.end
        else {
            streakBaseline = nil
            confirmedStreakDay = nil
            return
        }
        guard sections.contains(.streak), result.sectionIssues[.streak] == nil, let streak = result.streak else {
            return
        }
        if let baseline = streakBaseline, baseline.day == day, streak >= baseline.count {
            // A stable count alone cannot prove that LeetCode has applied today's increase.
            if daily.isCompleted == true, streak > baseline.count {
                confirmedStreakDay = day
            }
        } else {
            streakBaseline = (day, streak)
            confirmedStreakDay = nil
        }
    }

    private func clearDashboardCache() {
        snapshot = nil
        fetchedAt = [:]
        retryAfter = [:]
        streakBaseline = nil
        confirmedStreakDay = nil
    }

    private func refreshPendingSections() -> Task<Void, Never>? {
        guard !isWorking, let session else { return nil }
        // Preference changes bypass the ordinary refresh cooldown, but not rate-limit backoff.
        guard now() >= rateLimitedUntil else { return nil }
        let sections = dueSections(pendingSections.intersection(preferences.sections))
        pendingSections = []
        return refresh(session: session, sections: sections)
    }

    private func load(
        session: LeetCodeSession, username: String, sections: Set<DashboardSection>, ticket: Int
    ) async throws {
        let date = now()
        let result = try await client.dashboard(
            session: session, username: username, now: date, calendar: .current, sections: sections)
        try Task.checkCancellation()
        guard generation == ticket else { return }
        for section in sections {
            if result.sectionIssues[section] == nil {
                fetchedAt[section] = date
                retryAfter[section] = nil
            } else {
                retryAfter[section] = date.addingTimeInterval(60)
            }
        }
        snapshot = snapshot?.merging(result, sections: sections) ?? result
        updateStreakConfirmation(result, sections: sections, startedAt: date)
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
        clearDashboardCache()
        hasSavedSession = false
        isWorking = false
        didRestore = true
        message = nil
        nextRefresh = .distantPast
        pendingSections = []
        rateLimitedUntil = .distantPast
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
                await refreshPendingSections()?.value
            }
        }
        work = task
        return task
    }
}
