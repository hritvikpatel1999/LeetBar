import XCTest

final class LeetCodeClientTests: XCTestCase {
    func testContestRatingLoadsForTheRequestedUsername() async throws {
        let transport = MockLeetCodeTransport(responses: [
            (200, "{\"data\":{\"userContestRanking\":{\"rating\":1641.6,\"attendedContestsCount\":12}}}")
        ])
        let rating = try await LeetCodeClient(transport: transport).contestRating(
            username: "example", session: session())
        XCTAssertEqual(rating, .rated(1641.6))
        XCTAssertEqual(rating.formatted(locale: Locale(identifier: "en_US")), "1,642")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        XCTAssertEqual((body?["variables"] as? [String: String])?["username"], "example")
        XCTAssertTrue((body?["query"] as? String)?.contains("userContestRanking") == true)
    }

    func testContestRatingShowsUnratedOnlyForAValidUnratedResponse() async throws {
        for body in [
            "{\"data\":{\"userContestRanking\":null}}",
            "{\"data\":{\"userContestRanking\":{\"rating\":1500,\"attendedContestsCount\":0}}}",
            "{\"data\":{\"userContestRanking\":{\"rating\":null,\"attendedContestsCount\":0}}}",
        ] {
            let transport = MockLeetCodeTransport(responses: [(200, body)])
            let rating = try await LeetCodeClient(transport: transport).contestRating(
                username: "example", session: session())
            XCTAssertEqual(rating, .unrated)
            XCTAssertEqual(rating.formatted(), "Unrated")
        }
    }

    func testContestRatingFailuresAreNotReportedAsUnrated() async throws {
        for body in [
            "{\"data\":{}}",
            "{\"data\":{\"userContestRanking\":{\"rating\":null,\"attendedContestsCount\":2}}}",
            "{\"data\":{\"userContestRanking\":{\"rating\":-1,\"attendedContestsCount\":2}}}",
            "{\"data\":{\"userContestRanking\":{\"rating\":1500,\"attendedContestsCount\":-1}}}",
            "{\"data\":{\"userContestRanking\":null},\"errors\":[{\"message\":\"unavailable\"}]}",
        ] {
            let transport = MockLeetCodeTransport(responses: [(200, body)])
            do {
                _ = try await LeetCodeClient(transport: transport).contestRating(
                    username: "example", session: session())
                XCTFail("Expected invalid rating response")
            } catch {
                XCTAssertEqual(error as? LeetCodeError, .invalidResponse)
            }
        }
    }

    func testIsolatedKeychainRoundTrip() throws {
        let storage = KeychainSessionStore(service: "dev.leetbar.tests.\(UUID().uuidString)")
        defer { try? storage.delete() }
        XCTAssertNil(try storage.load())
        let original = try session()
        try storage.save(original)
        XCTAssertEqual(try storage.load(), original)
        let replacement = try LeetCodeSession(sessionCookie: "replacement", csrfToken: "replacement-csrf")
        try storage.save(replacement)
        XCTAssertEqual(try storage.load(), replacement)
        try storage.delete()
        XCTAssertNil(try storage.load())
    }

    func testDashboardKeepsAvailableSectionsWhenTotalsFail() async throws {
        let transport = MockLeetCodeTransport(responses: [
            (
                200,
                "{\"data\":{\"activeDailyCodingChallengeQuestion\":{\"date\":\"2026-10-05\",\"userStatus\":\"Finish\",\"link\":\"/problems/example/\",\"question\":{\"title\":\"Example\",\"titleSlug\":\"example\",\"difficulty\":\"Medium\"}}}}"
            ),
            (200, "{\"errors\":[{\"message\":\"unavailable\"}]}"),
            (200, "{\"data\":{\"topTwoContests\":[]}}"),
            (200, "{\"data\":{\"streakCounter\":{\"streakCount\":8}}}"),
            (200, "{\"data\":{\"userContestRanking\":{\"rating\":1641.6,\"attendedContestsCount\":12}}}"),
        ])
        let result = try await LeetCodeClient(transport: transport).dashboard(
            session: session(), username: "example", now: .now, calendar: .current)
        XCTAssertEqual(result.daily?.isCompleted, true)
        XCTAssertEqual(result.daily?.url?.host, "leetcode.com")
        XCTAssertNil(result.stats)
        XCTAssertEqual(result.contests?.count, 0)
        XCTAssertEqual(result.streak, 8)
        XCTAssertEqual(result.contestRating, .rated(1641.6))
        XCTAssertEqual(result.issues.count, 1)
    }

    func testDashboardLoadsStreakAndPreservesUnknownValues() async throws {
        let cases: [(String, Int?, Int)] = [
            ("{\"data\":{\"streakCounter\":{\"streakCount\":12}}}", 12, 0),
            ("{\"data\":{\"streakCounter\":{\"streakCount\":0}}}", 0, 0),
            ("{\"data\":{\"streakCounter\":null}}", nil, 1),
            ("{\"data\":{\"streakCounter\":{\"streakCount\":-1}}}", nil, 1),
            ("{\"errors\":[{\"message\":\"unavailable\"}]}", nil, 1),
        ]
        for (body, expectedStreak, expectedIssues) in cases {
            let transport = MockLeetCodeTransport(responses: [
                (
                    200,
                    "{\"data\":{\"activeDailyCodingChallengeQuestion\":{\"date\":\"2026-10-05\",\"userStatus\":\"Finish\",\"link\":\"/problems/example/\",\"question\":{\"title\":\"Example\",\"titleSlug\":\"example\",\"difficulty\":\"Easy\"}}}}"
                ),
                (200, "{\"data\":{\"submissionList\":{\"hasNext\":false,\"submissions\":[]}}}"),
                (200, "{\"data\":{\"topTwoContests\":[]}}"),
                (200, body),
                (200, "{\"data\":{\"userContestRanking\":null}}"),
            ])
            let result = try await LeetCodeClient(transport: transport).dashboard(
                session: session(), username: "example", now: .now, calendar: .current)
            XCTAssertEqual(result.streak, expectedStreak)
            XCTAssertEqual(result.contestRating, .unrated)
            XCTAssertEqual(result.issues.count, expectedIssues)
            XCTAssertEqual(result.daily?.isCompleted, true)
            XCTAssertEqual(result.stats, DailyStats(submissions: 0, problemsSolved: 0))
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.dropLast().last)
            let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            XCTAssertEqual(payload?["query"] as? String, "query LeetBarStreak { streakCounter { streakCount } }")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Cookie"), "LEETCODE_SESSION=test-session; csrftoken=test-csrf")
        }
    }

    func testDashboardKeepsOtherSectionsWhenRatingFails() async throws {
        let transport = MockLeetCodeTransport(responses: [
            (
                200,
                "{\"data\":{\"activeDailyCodingChallengeQuestion\":{\"date\":\"2026-10-05\",\"userStatus\":\"Finish\",\"link\":\"/problems/example/\",\"question\":{\"title\":\"Example\",\"titleSlug\":\"example\",\"difficulty\":\"Easy\"}}}}"
            ),
            (200, "{\"data\":{\"submissionList\":{\"hasNext\":false,\"submissions\":[]}}}"),
            (200, "{\"data\":{\"topTwoContests\":[]}}"),
            (200, "{\"data\":{\"streakCounter\":{\"streakCount\":8}}}"),
            (200, "{\"errors\":[{\"message\":\"unavailable\"}]}"),
        ])
        let result = try await LeetCodeClient(transport: transport).dashboard(
            session: session(), username: "example", now: .now, calendar: .current)
        XCTAssertNil(result.contestRating)
        XCTAssertEqual(result.daily?.isCompleted, true)
        XCTAssertEqual(result.stats, DailyStats(submissions: 0, problemsSolved: 0))
        XCTAssertEqual(result.streak, 8)
        XCTAssertEqual(result.contests?.count, 0)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.issues[0].hasPrefix("Contest rating:"))
    }

    private func session() throws -> LeetCodeSession {
        try LeetCodeSession(sessionCookie: "test-session", csrfToken: "test-csrf")
    }

    func testIdentityValidationAndRequestContainment() async throws {
        let transport = MockLeetCodeTransport(responses: [
            (200, "{\"data\":{\"userStatus\":{\"isSignedIn\":true,\"username\":\"example\"}}}")
        ])
        let account = try await LeetCodeClient(transport: transport).account(session: session())
        XCTAssertEqual(account.username, "example")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://leetcode.com/graphql/")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cookie"), "LEETCODE_SESSION=test-session; csrftoken=test-csrf")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRFToken"), "test-csrf")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("test-session"))
    }

    func testSignedOutAndServerFailuresDoNotBecomeSuccessfulConnections() async throws {
        for (status, body, expected) in [
            (200, "{\"data\":{\"userStatus\":{\"isSignedIn\":false,\"username\":\"\"}}}", LeetCodeError.signedOut),
            (401, "", .signedOut),
            (302, "", .signedOut),
            (403, "private server detail", .blocked),
            (429, "", .rateLimited),
            (200, "<html>Challenge page</html>", .invalidResponse),
            (200, "{\"errors\":[{\"message\":\"private server detail\"}]}", .invalidResponse),
        ] {
            let transport = MockLeetCodeTransport(responses: [(status, body)])
            do {
                _ = try await LeetCodeClient(transport: transport).account(session: session())
                XCTFail("Expected connection to fail")
            } catch {
                XCTAssertEqual(error as? LeetCodeError, expected)
                XCTAssertFalse(error.localizedDescription.contains("private server detail"))
            }
        }
    }

    func testPaginationCountsMoreThanTwentyAttemptsAndDistinctSolves() async throws {
        let now = Date(timeIntervalSince1970: 1_791_288_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let records = (0..<20).map { index in
            "{\"id\":\"\(index)\",\"timestamp\":\"\(Int(now.timeIntervalSince1970) - index)\",\"statusDisplay\":\"Accepted\",\"titleSlug\":\"same-problem\"}"
        }
        let first =
            "{\"data\":{\"submissionList\":{\"hasNext\":true,\"submissions\":[\(records.joined(separator: ","))]}}}"
        let second =
            "{\"data\":{\"submissionList\":{\"hasNext\":false,\"submissions\":[{\"id\":21,\"timestamp\":\(Int(now.timeIntervalSince1970) - 21),\"statusDisplay\":\"Wrong Answer\",\"titleSlug\":\"other-problem\"}]}}}"
        let transport = MockLeetCodeTransport(responses: [(200, first), (200, second)])
        let stats = try await LeetCodeClient(transport: transport).todayStats(
            session: session(), now: now, calendar: calendar)
        XCTAssertEqual(stats, DailyStats(submissions: 21, problemsSolved: 1))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let payload = try JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any]
        XCTAssertEqual((payload?["variables"] as? [String: Int])?["offset"], 20)
    }

    func testTruncatedHistoryDoesNotProduceExactTotals() async throws {
        let transport = MockLeetCodeTransport(responses: [
            (200, "{\"data\":{\"submissionList\":{\"hasNext\":true,\"submissions\":[]}}}")
        ])
        do {
            _ = try await LeetCodeClient(transport: transport).todayStats(
                session: session(), now: .now, calendar: .current)
            XCTFail("Expected incomplete history")
        } catch {
            XCTAssertEqual(error as? LeetCodeError, .incompleteHistory)
        }
    }

    func testDailyCompletionRecognizesServiceStatusValues() throws {
        let cases: [(String, Bool?)] = [
            ("Finish", true),
            ("Finished", true),
            ("FINISH", true),
            ("NotStart", false),
            ("NewStatus", nil),
        ]
        for (status, expected) in cases {
            let payload: [String: Any] = [
                "date": "2026-10-05",
                "userStatus": status,
                "link": "/problems/example/",
                "question": ["title": "Example", "titleSlug": "example", "difficulty": "Easy"],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let daily = try JSONDecoder().decode(LiveDailyChallenge.self, from: data)
            XCTAssertEqual(daily.isCompleted, expected, "Unexpected completion for \(status)")
        }
    }

    func testDailyCompletionDoesNotTreatUnknownStatusAsIncomplete() throws {
        let data = Data(
            "{\"date\":\"2026-10-05\",\"userStatus\":\"NewStatus\",\"link\":\"https://example.com/\",\"question\":{\"title\":\"Example\",\"titleSlug\":\"example\",\"difficulty\":\"Easy\"}}"
                .utf8)
        let daily = try JSONDecoder().decode(LiveDailyChallenge.self, from: data)
        XCTAssertNil(daily.isCompleted)
        XCTAssertNil(daily.url)
    }

    func testCredentialsTrimSurroundingWhitespace() throws {
        let session = try LeetCodeSession(sessionCookie: " test-session\n", csrfToken: " test-csrf ")
        XCTAssertEqual(session.sessionCookie, "test-session")
        XCTAssertEqual(session.csrfToken, "test-csrf")
    }

    func testCredentialsRejectEmptyAndInjectedCookieValues() {
        for invalid in ["", "a;b=c", "a\r\nCookie: b", "has space", "\"quoted\"", "nonascii-\u{E9}"] {
            XCTAssertThrowsError(try LeetCodeSession(sessionCookie: invalid, csrfToken: "test-csrf"))
            XCTAssertThrowsError(try LeetCodeSession(sessionCookie: "test-session", csrfToken: invalid))
        }
    }

    func testCredentialDescriptionsAreRedacted() throws {
        let session = try LeetCodeSession(sessionCookie: "test-session", csrfToken: "test-csrf")
        XCTAssertEqual(String(describing: session), "LeetCodeSession(redacted)")
        XCTAssertEqual(String(reflecting: session), "LeetCodeSession(redacted)")
    }
}

actor MockLeetCodeTransport: LeetCodeTransport {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, String)]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw LeetCodeError.invalidResponse }
        let (status, body) = responses.removeFirst()
        return (
            Data(body.utf8),
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}
