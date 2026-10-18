import XCTest

@MainActor
final class AccountStoreTests: XCTestCase {
    func testCompletedDailyIsCachedButUnconfirmedStreakKeepsPolling() async throws {
        let clock = TestClock()
        let transport = DashboardTransport()
        await transport.setDaily(status: "Finish")
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), now: { clock.date })
        await account.connect(testSession())?.value
        for _ in 1..<60 {
            clock.advance(60)
            await account.refresh()?.value
        }
        let queries = await transport.queries
        XCTAssertEqual(queries.count, 195)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 1)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStreak") }.count, 60)
        XCTAssertEqual(account.snapshot?.daily?.isCompleted, true)
        XCTAssertEqual(account.snapshot?.streak, 8)
    }

    func testDelayedStreakIncreaseIsConfirmedBeforeCaching() async throws {
        let clock = TestClock()
        let transport = DashboardTransport()
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), now: { clock.date })
        await account.connect(testSession())?.value
        for minute in 1..<60 {
            if minute == 1 { await transport.setDaily(status: "Finish") }
            if minute == 2 { await transport.setStreak(9) }
            clock.advance(60)
            await account.refresh()?.value
            XCTAssertEqual(account.snapshot?.streak, minute == 1 ? 8 : 9)
        }
        let queries = await transport.queries
        XCTAssertEqual(queries.count, 139)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 2)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStreak") }.count, 3)
    }

    func testIncompleteUnknownAndInvalidDailyDatesKeepPolling() async throws {
        let cases: [(String, String?)] = [
            ("2027-01-15", "NotStart"), ("2027-01-15", nil), ("2027-01-15", "unexpected"),
            ("2027-01-14", "Finish"), ("2027-01-16", "Finish"),
            ("2027-02-30", "Finish"), ("not-a-date", "Finish"),
        ]
        for (date, status) in cases {
            let clock = TestClock()
            let transport = DashboardTransport()
            await transport.setDaily(date: date, status: status)
            let account = AccountStore(
                storage: TestSessionStore(), client: LeetCodeClient(transport: transport), now: { clock.date })
            await account.connect(testSession())?.value
            clock.advance(60)
            await account.refresh()?.value
            let queries = await transport.queries
            XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 2, "\(date): \(status ?? "nil")")
            XCTAssertEqual(queries.filter { $0.contains("LeetBarStreak") }.count, 2)
        }
    }

    func testCompletionAndConfirmedStreakExpireAtUTCReset() async throws {
        let clock = TestClock()
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        clock.date = calendar.startOfDay(for: clock.date).addingTimeInterval(86_220)
        let transport = DashboardTransport()
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), now: { clock.date })
        await account.connect(testSession())?.value
        await transport.setDaily(status: "Finish")
        await transport.setStreak(9)
        clock.advance(60)
        await account.refresh()?.value
        clock.advance(60)
        await account.refresh()?.value
        var queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 2)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStreak") }.count, 2)
        clock.advance(60)
        // Even a stale completed response for yesterday must not lock the new day.
        await account.refresh()?.value
        clock.advance(60)
        await transport.setDaily(date: "2027-01-16", status: "NotStart")
        await account.refresh()?.value
        queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 4)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStreak") }.count, 4)
        XCTAssertEqual(account.snapshot?.daily?.isCompleted, false)
    }

    func testDailyDateDefinesUTCBoundaries() throws {
        let daily = LiveDailyChallenge(
            date: "2027-01-15", userStatus: "Finish", link: "/problems/example/",
            question: .init(title: "Example", titleSlug: "example", difficulty: "Easy"))
        let day = try XCTUnwrap(daily.dayInterval)
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(formatter.string(from: day.start), "2027-01-15T00:00:00Z")
        XCTAssertEqual(formatter.string(from: day.end), "2027-01-16T00:00:00Z")
    }

    func testFailedStreakResponseCannotConfirmAnIncrease() async throws {
        let clock = TestClock()
        let transport = DashboardTransport()
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), now: { clock.date })
        await account.connect(testSession())?.value
        await transport.setDaily(status: "Finish")
        await transport.setStreak(9)
        await transport.setFailure("LeetBarStreak", status: 500)
        clock.advance(60)
        await account.refresh()?.value
        XCTAssertNil(account.snapshot?.streak)
        XCTAssertEqual(account.snapshot?.issues.count, 1)
        await transport.setFailure("LeetBarStreak", status: nil)
        clock.advance(60)
        await account.refresh()?.value
        XCTAssertEqual(account.snapshot?.streak, 9)
        clock.advance(60)
        await account.refresh()?.value
        let queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 2)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStreak") }.count, 3)
        XCTAssertEqual(account.snapshot?.issues.count, 0)
    }

    func testReconnectAndDisconnectClearCompletedDayAndStreakLocks() async throws {
        let clock = TestClock()
        let transport = DashboardTransport()
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), now: { clock.date })
        await account.connect(testSession())?.value
        await transport.setDaily(status: "Finish")
        await transport.setStreak(9)
        clock.advance(60)
        await account.refresh()?.value
        for reconnect in [true, false] {
            if !reconnect { account.disconnect() }
            await account.connect(testSession())?.value
            clock.advance(60)
            await account.refresh()?.value
        }
        let queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 4)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStreak") }.count, 6)
    }

    func testMeasuredBusyHourRequestSavings() async throws {
        let scenarios: [(DashboardPreferences, Int)] = [
            (DashboardPreferences(), 254),
            (DashboardPreferences(showStudyPlans: false), 242),
            (DashboardPreferences(showToday: false, showContests: false, showStudyPlans: false), 181),
        ]
        for (preferences, expected) in scenarios {
            let clock = TestClock()
            let transport = DashboardTransport()
            let account = AccountStore(
                storage: TestSessionStore(), client: LeetCodeClient(transport: transport),
                preferences: preferences, now: { clock.date })
            await account.connect(testSession())?.value
            for _ in 1..<60 {
                clock.advance(60)
                await account.refresh()?.value
            }
            let queries = await transport.queries
            XCTAssertEqual(queries.count, expected)
            XCTAssertEqual(queries.filter { $0.contains("LeetBarAccount") }.count, 60)
            XCTAssertEqual(
                queries.filter { $0.contains("LeetBarStudyPlans") }.count, preferences.showStudyPlans ? 12 : 0)
            XCTAssertEqual(queries.filter { $0.contains("LeetBarSubmissions") }.count, preferences.showToday ? 60 : 0)
            XCTAssertEqual(queries.filter { $0.contains("LeetBarContests") }.count, preferences.showContests ? 1 : 0)
            XCTAssertEqual(queries.filter { $0.contains("LeetBarStreak") }.count, 60)
        }
    }

    func testColdConnectAndRestoredRefreshSkipDisabledSections() async throws {
        for connect in [true, false] {
            let storage = TestSessionStore()
            let transport = DashboardTransport()
            let preferences = DashboardPreferences(showToday: false, showContests: false, showStudyPlans: false)
            let account = AccountStore(
                storage: storage, client: LeetCodeClient(transport: transport), preferences: preferences)
            if connect {
                await account.connect(testSession())?.value
            } else {
                try storage.save(testSession())
                account.restore()
                await account.refresh()?.value
            }
            let queries = await transport.queries
            XCTAssertEqual(queries.count, 4)
            XCTAssertEqual(account.snapshot?.streak, 8)
            XCTAssertNil(account.snapshot?.stats)
            XCTAssertNil(account.snapshot?.studyPlans)
            XCTAssertNil(account.snapshot?.contests)
            XCTAssertEqual(account.snapshot?.issues, [])
        }
    }

    func testCadenceBoundariesAndCachedValuesArePreserved() async throws {
        let clock = TestClock()
        let transport = DashboardTransport()
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), now: { clock.date })
        await account.connect(testSession())?.value
        clock.advance(59)
        await account.refresh()?.value
        var count = await transport.queries.count
        XCTAssertEqual(count, 7)
        clock.advance(1)
        await account.refresh()?.value
        count = await transport.queries.count
        XCTAssertEqual(count, 11)
        XCTAssertEqual(account.snapshot?.contestRating, .rated(1500))
        XCTAssertEqual(account.snapshot?.studyPlans?.count, 0)
        clock.advance(239)
        await account.refresh()?.value
        var queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStudyPlans") }.count, 1)
        clock.advance(60)
        await account.refresh()?.value
        queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStudyPlans") }.count, 2)
        clock.advance(3240)
        await account.refresh()?.value
        queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarContestRating") }.count, 1)
        clock.advance(60)
        await account.refresh()?.value
        queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarContestRating") }.count, 2)
    }

    func testEnablingSectionsBypassesCooldownAndReusesFreshCache() async throws {
        let clock = TestClock()
        let transport = DashboardTransport()
        var preferences = DashboardPreferences(showToday: false, showContests: false, showStudyPlans: false)
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport),
            preferences: preferences, now: { clock.date })
        await account.connect(testSession())?.value
        preferences.showStudyPlans = true
        await account.updatePreferences(preferences)?.value
        var queries = await transport.queries
        XCTAssertEqual(queries.count, 6)
        XCTAssertTrue(queries.last?.contains("LeetBarStudyPlans") == true)
        preferences.showStudyPlans = false
        await account.updatePreferences(preferences)?.value
        preferences.showStudyPlans = true
        await account.updatePreferences(preferences)?.value
        queries = await transport.queries
        XCTAssertEqual(queries.count, 6)
        preferences.showStudyPlans = false
        await account.updatePreferences(preferences)?.value
        clock.advance(300)
        preferences = DashboardPreferences()
        await account.updatePreferences(preferences)?.value
        queries = await transport.queries
        XCTAssertEqual(queries.count, 10)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 1)
        XCTAssertNotNil(account.snapshot?.daily)
        XCTAssertNotNil(account.snapshot?.stats)
        XCTAssertNotNil(account.snapshot?.contests)
    }

    func testNewlyEnabledSectionIsQueuedDuringConnection() async throws {
        let transport = DashboardTransport(pauseOperation: "LeetBarAccount")
        var preferences = DashboardPreferences(showStudyPlans: false)
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), preferences: preferences)
        let work = account.connect(testSession())
        await transport.waitUntilPaused()
        preferences.showStudyPlans = true
        account.updatePreferences(preferences)
        await transport.resume()
        await work?.value
        // Preferences changed before dashboard work started, so it joins that same fetch.
        XCTAssertNotNil(account.snapshot?.studyPlans)
        let queries = await transport.queries
        XCTAssertEqual(queries.count, 7)
    }

    func testEnablingDuringDashboardFetchQueuesOnlyMissingSection() async throws {
        let transport = DashboardTransport(pauseOperation: "LeetBarDaily")
        var preferences = DashboardPreferences(showStudyPlans: false)
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), preferences: preferences)
        let work = account.connect(testSession())
        await transport.waitUntilPaused()
        preferences.showStudyPlans = true
        account.updatePreferences(preferences)
        await transport.resume()
        await work?.value
        let queries = await transport.queries
        XCTAssertEqual(queries.count, 8)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarDaily") }.count, 1)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarStudyPlans") }.count, 1)
        XCTAssertNotNil(account.snapshot?.studyPlans)
        XCTAssertFalse(account.isWorking)
    }

    func testDisablingQueuedSectionPreventsItsFetch() async throws {
        let transport = DashboardTransport(pauseOperation: "LeetBarDaily")
        var preferences = DashboardPreferences(showStudyPlans: false)
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), preferences: preferences)
        let work = account.connect(testSession())
        await transport.waitUntilPaused()
        preferences.showStudyPlans = true
        account.updatePreferences(preferences)
        preferences.showStudyPlans = false
        account.updatePreferences(preferences)
        await transport.resume()
        await work?.value
        let queries = await transport.queries
        XCTAssertEqual(queries.count, 6)
        XCTAssertNil(account.snapshot?.studyPlans)
    }

    func testPartialRefreshDoesNotRelabelYesterdaysStatsAsToday() async throws {
        let clock = TestClock()
        clock.date = Calendar.current.startOfDay(for: clock.date).addingTimeInterval(86_390)
        let transport = DashboardTransport()
        var preferences = DashboardPreferences(showStudyPlans: false)
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport),
            preferences: preferences, now: { clock.date })
        await account.connect(testSession())?.value
        XCTAssertNotNil(account.snapshot?.stats(asOf: clock.date))
        clock.advance(20)
        preferences.showStudyPlans = true
        await account.updatePreferences(preferences)?.value
        XCTAssertNil(account.snapshot?.stats(asOf: clock.date))
        clock.advance(60)
        await account.refresh()?.value
        XCTAssertNotNil(account.snapshot?.stats(asOf: clock.date))
    }

    func testRateLimitStopsDashboardAndNewlyEnabledRequests() async throws {
        let clock = TestClock()
        let transport = DashboardTransport()
        var preferences = DashboardPreferences(showStudyPlans: false)
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport),
            preferences: preferences, now: { clock.date })
        await account.connect(testSession())?.value
        await transport.setFailure("LeetBarDaily", status: 429)
        clock.advance(60)
        await account.refresh()?.value
        var queries = await transport.queries
        XCTAssertEqual(queries.count, 8)
        XCTAssertNotNil(account.message)
        preferences.showStudyPlans = true
        await account.updatePreferences(preferences)?.value
        clock.advance(299)
        await account.refresh()?.value
        queries = await transport.queries
        XCTAssertEqual(queries.count, 8)
        await transport.setFailure("LeetBarDaily", status: nil)
        clock.advance(1)
        await account.refresh()?.value
        XCTAssertNotNil(account.snapshot?.studyPlans)
    }

    func testFailedSectionRetriesWithoutWaitingForLongCacheLifetime() async throws {
        let clock = TestClock()
        let transport = DashboardTransport()
        await transport.setFailure("LeetBarContests", status: 500)
        let account = AccountStore(
            storage: TestSessionStore(), client: LeetCodeClient(transport: transport), now: { clock.date })
        await account.connect(testSession())?.value
        XCTAssertEqual(account.snapshot?.issues.count, 1)
        await transport.setFailure("LeetBarContests", status: nil)
        clock.advance(60)
        await account.refresh()?.value
        XCTAssertEqual(account.snapshot?.issues.count, 0)
        let queries = await transport.queries
        XCTAssertEqual(queries.filter { $0.contains("LeetBarContests") }.count, 2)
        XCTAssertEqual(queries.filter { $0.contains("LeetBarContestRating") }.count, 1)
    }

    func testReconnectAndDisconnectInvalidateCache() async throws {
        let transport = DashboardTransport()
        let account = AccountStore(storage: TestSessionStore(), client: LeetCodeClient(transport: transport))
        await account.connect(testSession())?.value
        await account.connect(testSession())?.value
        account.disconnect()
        await account.connect(testSession())?.value
        let queries = await transport.queries
        XCTAssertEqual(queries.count, 21)
    }

    private func testSession() -> LeetCodeSession {
        try! LeetCodeSession(sessionCookie: "test-session", csrfToken: "test-csrf")
    }

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

    @MainActor
    private final class TestClock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
    }

    private actor DashboardTransport: LeetCodeTransport {
        private(set) var queries: [String] = []
        private var failures: [String: Int] = [:]
        private var pauseOperation: String?
        private var paused: CheckedContinuation<Void, Never>?
        private var waiter: CheckedContinuation<Void, Never>?
        private var dailyDate = "2027-01-15"
        private var dailyStatus: String? = "NotStart"
        private var streak = 8

        init(pauseOperation: String? = nil) { self.pauseOperation = pauseOperation }

        func setFailure(_ operation: String, status: Int?) { failures[operation] = status }

        func setDaily(date: String = "2027-01-15", status: String?) {
            dailyDate = date
            dailyStatus = status
        }

        func setStreak(_ value: Int) { streak = value }

        func waitUntilPaused() async {
            if paused != nil { return }
            await withCheckedContinuation { waiter = $0 }
        }

        func resume() {
            pauseOperation = nil
            paused?.resume()
            paused = nil
        }

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let query = try XCTUnwrap(body?["query"] as? String)
            queries.append(query)
            if let pauseOperation, query.contains(pauseOperation) {
                await withCheckedContinuation {
                    paused = $0
                    waiter?.resume()
                    waiter = nil
                }
            }
            let responses = [
                "LeetBarAccount": #"{"userStatus":{"isSignedIn":true,"username":"example"}}"#,
                "LeetBarDaily":
                    """
                {"activeDailyCodingChallengeQuestion":{"date":"\(dailyDate)","userStatus":\(dailyStatus.map { "\"\($0)\"" } ?? "null"),"link":"/problems/example/","question":{"title":"Example","titleSlug":"example","difficulty":"Easy"}}}
                """,
                "LeetBarSubmissions": #"{"submissionList":{"hasNext":false,"submissions":[]}}"#,
                "LeetBarContests": #"{"topTwoContests":[]}"#,
                "LeetBarStudyPlans": #"{"studyPlanV2UserProgresses":{"planUserProgresses":[]}}"#,
                "LeetBarStreak": "{\"streakCounter\":{\"streakCount\":\(streak)}}",
                "LeetBarContestRating": #"{"userContestRanking":{"rating":1500,"attendedContestsCount":1}}"#,
            ]
            let operation = try XCTUnwrap(responses.keys.first { query.contains($0) })
            let payload = try XCTUnwrap(responses[operation])
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!, statusCode: failures[operation] ?? 200, httpVersion: nil, headerFields: nil))
            return (Data("{\"data\":\(payload)}".utf8), response)
        }
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
    func dashboard(
        session: LeetCodeSession, username: String, now: Date, calendar: Calendar,
        sections: Set<DashboardSection>
    ) async throws
        -> LiveDashboard
    {
        guard username == "example" else { throw LeetCodeError.invalidResponse }
        return LiveDashboard(
            daily: nil, stats: DailyStats(submissions: 0, problemsSolved: 0), contests: [], studyPlans: [], streak: nil,
            contestRating: .rated(1641.6), checkedAt: now,
            sectionIssues: [:])
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
    func dashboard(
        session: LeetCodeSession, username: String, now: Date, calendar: Calendar,
        sections: Set<DashboardSection>
    ) async throws
        -> LiveDashboard
    {
        throw LeetCodeError.invalidResponse
    }
}
