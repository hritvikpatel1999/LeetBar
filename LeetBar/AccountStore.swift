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
    private let logger: DiagnosticLogger

    init(
        storage: any SessionStoring = KeychainSessionStore(), client: any LeetCodeServing = LeetCodeClient(),
        preferences: DashboardPreferences = DashboardPreferences(), now: @escaping () -> Date = { .now },
        logger: DiagnosticLogger = .disabled
    ) {
        self.storage = storage
        self.client = client
        self.preferences = preferences
        self.now = now
        self.logger = logger
    }

    func restore() {
        guard !didRestore else { return }
        didRestore = true
        logger.log(.info, .sessionRestoreStarted)
        do {
            session = try storage.load()
            hasSavedSession = session != nil
            logger.log(.info, session == nil ? .sessionMissing : .sessionRestored)
        } catch {
            logger.logFailure(.sessionRestoreFailed, error: error)
            hasSavedSession = true
            message = LeetCodeClient.message(for: error)
        }
    }

    @discardableResult
    func connect(_ candidate: LeetCodeSession) -> Task<Void, Never>? {
        guard !isWorking else { return nil }
        return start { [self] ticket in
            logger.log(.info, .connectionStarted, cycleID: DiagnosticContext.cycleID)
            do {
                let account = try await client.account(session: candidate)
                guard let username = account.username, !username.isEmpty else { throw LeetCodeError.signedOut }
                try Task.checkCancellation()
                guard generation == ticket else { return }
                logger.log(.info, .connectionVerified, cycleID: DiagnosticContext.cycleID)
                logger.log(.info, .sessionSaveStarted, cycleID: DiagnosticContext.cycleID)
                do {
                    try storage.save(candidate)
                    logger.log(.info, .sessionSaved, cycleID: DiagnosticContext.cycleID)
                } catch {
                    logger.logFailure(.sessionSaveFailed, error: error)
                    throw error
                }
                session = candidate
                hasSavedSession = true
                didRestore = true
                self.username = username
                clearDashboardCache()
                rateLimitedUntil = .distantPast
                nextRefresh = now().addingTimeInterval(60)
                try await load(session: candidate, username: username, sections: preferences.sections, ticket: ticket)
            } catch {
                logger.logFailure(
                    Task.isCancelled ? .connectionCancelled : .connectionFailed, error: error)
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
        guard !isWorking, let session else {
            logger.log(.debug, .refreshDeferred, reason: isWorking ? .busy : .noSession)
            return nil
        }
        guard now() >= nextRefresh else {
            logger.log(.debug, .refreshDeferred, reason: now() < rateLimitedUntil ? .rateLimited : .cooldown)
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
                logger.log(.info, .sessionVerificationStarted, cycleID: DiagnosticContext.cycleID)
                let account = try await client.account(session: session)
                guard let username = account.username, !username.isEmpty else { throw LeetCodeError.signedOut }
                try Task.checkCancellation()
                guard generation == ticket else { return }
                logger.log(.info, .sessionVerified, cycleID: DiagnosticContext.cycleID)
                if self.username != nil && self.username != username {
                    logger.log(.info, .accountChanged, cycleID: DiagnosticContext.cycleID)
                    clearDashboardCache()
                }
                try await load(
                    session: session, username: username,
                    sections: self.username != nil && self.username != username ? preferences.sections : sections,
                    ticket: ticket)
                self.username = username
            } catch {
                logger.logFailure(.refreshFailed, error: error)
                guard generation == ticket, !Task.isCancelled else { return }
                if error as? LeetCodeError == .signedOut {
                    logger.log(.warning, .sessionExpired, cycleID: DiagnosticContext.cycleID, reason: .signedOut)
                    self.session = nil
                    username = nil
                    clearDashboardCache()
                    pendingSections = []
                }
                if error as? LeetCodeError == .rateLimited {
                    logger.log(.warning, .refreshDeferred, cycleID: DiagnosticContext.cycleID, reason: .rateLimited)
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
        for section in enabled {
            logger.log(.debug, .sectionQueued, operation: DiagnosticOperation(section: section))
        }
        preferences = value
        pendingSections.formUnion(enabled)
        pendingSections.formIntersection(value.sections)
        return refreshPendingSections()
    }

    private func dueSections(_ sections: Set<DashboardSection>) -> Set<DashboardSection> {
        let date = now()
        let completedDay = completedChallengeDay(at: date)
        for section in DashboardSection.allCases where !preferences.sections.contains(section) {
            logger.log(.debug, .sectionSkipped, operation: DiagnosticOperation(section: section), reason: .disabled)
        }
        return sections.filter { section in
            if section == .daily, completedDay != nil { return skip(section, reason: .completedDay) }
            if section == .streak, let completedDay, confirmedStreakDay == completedDay {
                return skip(section, reason: .confirmedStreak)
            }
            if let retry = retryAfter[section], date < retry { return skip(section, reason: .cooldown) }
            guard let fetched = fetchedAt[section] else { return true }
            if [.daily, .today, .streak].contains(section),
                !Calendar.current.isDate(fetched, inSameDayAs: date)
            {
                return true
            }
            if date.timeIntervalSince(fetched) >= section.refreshInterval { return true }
            return skip(section, reason: .cacheFresh)
        }
    }

    private func skip(_ section: DashboardSection, reason: DiagnosticReason) -> Bool {
        logger.log(.debug, .sectionSkipped, operation: DiagnosticOperation(section: section), reason: reason)
        return false
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
        logger.log(.debug, .cacheCleared, cycleID: DiagnosticContext.cycleID)
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
        logger.log(.info, .refreshStarted, cycleID: DiagnosticContext.cycleID, count: sections.count)
        let result = try await client.dashboard(
            session: session, username: username, now: date, calendar: .current, sections: sections)
        try Task.checkCancellation()
        guard generation == ticket else { return }
        for section in sections {
            if result.sectionIssues[section] == nil {
                fetchedAt[section] = date
                retryAfter[section] = nil
            } else {
                logger.log(
                    .warning, .sectionFailed, operation: DiagnosticOperation(section: section),
                    cycleID: DiagnosticContext.cycleID)
                retryAfter[section] = date.addingTimeInterval(60)
            }
        }
        snapshot = snapshot?.merging(result, sections: sections) ?? result
        updateStreakConfirmation(result, sections: sections, startedAt: date)
        logger.log(.info, .refreshFinished, cycleID: DiagnosticContext.cycleID, count: result.sectionIssues.count)
    }

    func disconnect() {
        logger.log(.info, .disconnectStarted)
        do {
            try storage.delete()
        } catch {
            logger.logFailure(.disconnectFailed, error: error)
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
        logger.log(.info, .disconnected)
        logger.flush()
    }

    private func start(_ operation: @escaping @MainActor (Int) async -> Void) -> Task<Void, Never> {
        generation += 1
        let ticket = generation
        isWorking = true
        message = nil
        let task = Task { @MainActor in
            await DiagnosticContext.$cycleID.withValue(UUID()) { await operation(ticket) }
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
