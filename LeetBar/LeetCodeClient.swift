import Foundation

enum LeetCodeError: LocalizedError, Equatable {
    case signedOut
    case blocked
    case rateLimited
    case invalidResponse
    case incompleteHistory
    case network

    var errorDescription: String? {
        switch self {
        case .signedOut: "Your LeetCode session expired or is invalid. Connect again in Settings."
        case .blocked: "LeetCode rejected the request. Sign in through your browser and reconnect with fresh cookies."
        case .rateLimited: "LeetCode is limiting requests. Wait a few minutes before refreshing."
        case .invalidResponse: "LeetCode returned an unexpected response. Its website API may have changed."
        case .incompleteHistory: "Submission history is incomplete. Totals are unavailable."
        case .network: "Could not reach LeetCode. Check your connection and try again."
        }
    }
}

protocol LeetCodeTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct LeetCodeURLTransport: LeetCodeTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LeetCodeError.invalidResponse }
        return (data, response)
    }
}

struct LeetCodeAccount: Decodable, Sendable {
    let isSignedIn: Bool
    let username: String?
}

enum ContestRating: Equatable, Sendable {
    case unrated
    case rated(Double)

    func formatted(locale: Locale = .current) -> String {
        switch self {
        case .unrated: "Unrated"
        case .rated(let rating): rating.formatted(.number.precision(.fractionLength(0)).locale(locale))
        }
    }
}

struct LiveDailyChallenge: Decodable, Sendable {
    struct Question: Decodable, Sendable {
        let title: String
        let titleSlug: String
        let difficulty: String
    }

    let date: String
    let userStatus: String?
    let link: String
    let question: Question

    var isCompleted: Bool? {
        switch userStatus?.lowercased() {
        case "finish", "finished": true
        case "notstart": false
        default: nil
        }
    }

    var url: URL? {
        guard let url = URL(string: link, relativeTo: URL(string: "https://leetcode.com"))?.absoluteURL,
            url.scheme == "https", url.host == "leetcode.com",
            url.user == nil, url.password == nil, url.port == nil
        else { return nil }
        return url
    }
}

struct LiveContest: Decodable, Sendable, Identifiable {
    let title: String
    let titleSlug: String
    let startTime: TimeInterval
    let duration: TimeInterval

    var id: String { titleSlug }
    var start: Date { Date(timeIntervalSince1970: startTime) }
    var end: Date { start.addingTimeInterval(duration) }
    var url: URL {
        var components = URLComponents(string: "https://leetcode.com")!
        components.path = "/contest/\(titleSlug)/"
        return components.url!
    }
}

struct LiveDashboard: Sendable {
    let daily: LiveDailyChallenge?
    let stats: DailyStats?
    let contests: [LiveContest]?
    let streak: Int?
    let contestRating: ContestRating?
    let checkedAt: Date
    let issues: [String]
}

protocol LeetCodeServing: Sendable {
    func account(session: LeetCodeSession) async throws -> LeetCodeAccount
    func dashboard(session: LeetCodeSession, username: String, now: Date, calendar: Calendar) async throws
        -> LiveDashboard
}

struct LeetCodeClient: LeetCodeServing {
    let transport: any LeetCodeTransport
    let maxSubmissionPages: Int

    init(transport: any LeetCodeTransport = LeetCodeURLTransport(), maxSubmissionPages: Int = 25) {
        self.transport = transport
        self.maxSubmissionPages = maxSubmissionPages
    }

    func account(session: LeetCodeSession) async throws -> LeetCodeAccount {
        struct Payload: Decodable { let userStatus: LeetCodeAccount }
        let payload: Payload = try await query(
            "query LeetBarAccount { userStatus { isSignedIn username } }", session: session
        )
        guard payload.userStatus.isSignedIn,
            let username = payload.userStatus.username, !username.isEmpty
        else { throw LeetCodeError.signedOut }
        return payload.userStatus
    }

    func contestRating(username: String, session: LeetCodeSession) async throws -> ContestRating {
        struct Ranking: Decodable {
            let rating: Double?
            let attendedContestsCount: Int
        }
        struct Payload: Decodable {
            let userContestRanking: Ranking?

            enum CodingKeys: String, CodingKey { case userContestRanking }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                userContestRanking = try container.decode(Ranking?.self, forKey: .userContestRanking)
            }
        }
        guard !username.isEmpty else { throw LeetCodeError.invalidResponse }
        let payload: Payload = try await query(
            """
            query LeetBarContestRating($username: String!) {
                userContestRanking(username: $username) { rating attendedContestsCount }
            }
            """, variables: ["username": .string(username)], session: session)
        guard let ranking = payload.userContestRanking else { return .unrated }
        guard ranking.attendedContestsCount >= 0 else { throw LeetCodeError.invalidResponse }
        if ranking.attendedContestsCount == 0 { return .unrated }
        guard let rating = ranking.rating, rating.isFinite, rating >= 0 else {
            throw LeetCodeError.invalidResponse
        }
        return .rated(rating)
    }

    func dashboard(session: LeetCodeSession, username: String, now: Date, calendar: Calendar) async throws
        -> LiveDashboard
    {
        var issues: [String] = []
        var daily: LiveDailyChallenge?
        var stats: DailyStats?
        var contests: [LiveContest]?
        var streak: Int?
        var rating: ContestRating?

        do {
            struct Payload: Decodable { let activeDailyCodingChallengeQuestion: LiveDailyChallenge? }
            let payload: Payload = try await query(
                """
                query LeetBarDaily {
                    activeDailyCodingChallengeQuestion {
                        date userStatus link question { title titleSlug difficulty }
                    }
                }
                """, session: session)
            guard let challenge = payload.activeDailyCodingChallengeQuestion else {
                throw LeetCodeError.invalidResponse
            }
            daily = challenge
        } catch {
            if error as? LeetCodeError == .signedOut || error is CancellationError { throw error }
            issues.append("Daily problem: \(Self.message(for: error))")
        }

        do {
            stats = try await todayStats(session: session, now: now, calendar: calendar)
        } catch {
            if error as? LeetCodeError == .signedOut || error is CancellationError { throw error }
            issues.append("Today: \(Self.message(for: error))")
        }

        do {
            struct Payload: Decodable { let topTwoContests: [LiveContest] }
            let payload: Payload = try await query(
                """
                query LeetBarContests { topTwoContests { title titleSlug startTime duration } }
                """, session: session)
            contests = payload.topTwoContests.filter { $0.end > now }.sorted { $0.start < $1.start }
        } catch {
            if error as? LeetCodeError == .signedOut || error is CancellationError { throw error }
            issues.append("Contests: \(Self.message(for: error))")
        }

        do {
            struct Counter: Decodable { let streakCount: Int }
            struct Payload: Decodable { let streakCounter: Counter? }
            let payload: Payload = try await query(
                "query LeetBarStreak { streakCounter { streakCount } }", session: session)
            guard let counter = payload.streakCounter, counter.streakCount >= 0 else {
                throw LeetCodeError.invalidResponse
            }
            streak = counter.streakCount
        } catch {
            if error as? LeetCodeError == .signedOut || error is CancellationError { throw error }
            issues.append("Streak: \(Self.message(for: error))")
        }

        do {
            rating = try await contestRating(username: username, session: session)
        } catch {
            if error as? LeetCodeError == .signedOut || error is CancellationError { throw error }
            issues.append("Contest rating: \(Self.message(for: error))")
        }

        return LiveDashboard(
            daily: daily, stats: stats, contests: contests, streak: streak, contestRating: rating,
            checkedAt: now, issues: issues)
    }

    func todayStats(session: LeetCodeSession, now: Date, calendar: Calendar) async throws -> DailyStats {
        struct Payload: Decodable { let submissionList: SubmissionPage? }
        let start = calendar.startOfDay(for: now)
        var submissions: [Submission] = []
        var seenIDs = Set<String>()
        var previousTimestamp = TimeInterval.infinity

        for pageIndex in 0..<max(0, maxSubmissionPages) {
            try Task.checkCancellation()
            let payload: Payload = try await query(
                """
                query LeetBarSubmissions($offset: Int!, $limit: Int!) {
                    submissionList(offset: $offset, limit: $limit) {
                        hasNext submissions { id timestamp statusDisplay titleSlug }
                    }
                }
                """, variables: ["offset": .integer(pageIndex * 20), "limit": .integer(20)], session: session)
            guard let page = payload.submissionList else { throw LeetCodeError.invalidResponse }
            var crossedDayBoundary = false
            var newRecords = 0

            for record in page.submissions {
                guard seenIDs.insert(record.id.value).inserted else { continue }
                newRecords += 1
                guard record.timestamp.value <= previousTimestamp, !record.titleSlug.isEmpty else {
                    throw LeetCodeError.incompleteHistory
                }
                previousTimestamp = record.timestamp.value
                let date = Date(timeIntervalSince1970: record.timestamp.value)
                if date < start { crossedDayBoundary = true }
                if date >= start && date <= now {
                    submissions.append(
                        Submission(
                            problemSlug: record.titleSlug,
                            submittedAt: date,
                            accepted: record.statusDisplay == "Accepted"
                        ))
                }
            }

            if crossedDayBoundary || !page.hasNext {
                return DailyStats.calculate(submissions: submissions, on: now, calendar: calendar)
            }
            guard newRecords > 0, page.submissions.count == 20 else {
                throw LeetCodeError.incompleteHistory
            }
        }
        throw LeetCodeError.incompleteHistory
    }

    static func message(for error: Error) -> String {
        if let error = error as? LeetCodeError { return error.localizedDescription }
        if let error = error as? SessionStorageError { return error.localizedDescription }
        return LeetCodeError.network.localizedDescription
    }

    private func query<Payload: Decodable>(
        _ query: String,
        variables: [String: GraphQLVariable] = [:],
        session: LeetCodeSession
    ) async throws -> Payload {
        var request = URLRequest(url: URL(string: "https://leetcode.com/graphql/")!)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://leetcode.com", forHTTPHeaderField: "Origin")
        request.setValue("https://leetcode.com/", forHTTPHeaderField: "Referer")
        request.setValue("LeetBar/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(
            "LEETCODE_SESSION=\(session.sessionCookie); csrftoken=\(session.csrfToken)", forHTTPHeaderField: "Cookie")
        request.setValue(session.csrfToken, forHTTPHeaderField: "X-CSRFToken")
        request.httpBody = try JSONEncoder().encode(GraphQLBody(query: query, variables: variables))
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            try Task.checkCancellation()
            throw LeetCodeError.network
        }
        switch response.statusCode {
        case 200: break
        case 401, 300..<400: throw LeetCodeError.signedOut
        case 403: throw LeetCodeError.blocked
        case 429: throw LeetCodeError.rateLimited
        default: throw LeetCodeError.invalidResponse
        }
        guard let envelope = try? JSONDecoder().decode(GraphQLResponse<Payload>.self, from: data),
            envelope.errors?.isEmpty != false, let payload = envelope.data
        else { throw LeetCodeError.invalidResponse }
        return payload
    }
}

private enum GraphQLVariable: Encodable {
    case integer(Int)
    case string(String)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

private struct GraphQLBody: Encodable {
    let query: String
    let variables: [String: GraphQLVariable]
}

private struct GraphQLResponse<Payload: Decodable>: Decodable {
    struct Failure: Decodable {}
    let data: Payload?
    let errors: [Failure]?
}

private struct SubmissionPage: Decodable {
    struct Record: Decodable {
        let id: StringOrNumber
        let timestamp: UnixTimestamp
        let statusDisplay: String
        let titleSlug: String
    }
    let hasNext: Bool
    let submissions: [Record]
}

private struct StringOrNumber: Decodable {
    let value: String
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), !string.isEmpty {
            value = string
        } else {
            value = String(try container.decode(Int64.self))
        }
    }
}

private struct UnixTimestamp: Decodable {
    let value: TimeInterval
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let number = Double(try container.decode(String.self)) {
            value = number
        } else {
            throw LeetCodeError.invalidResponse
        }
        guard value.isFinite, value > 0 else { throw LeetCodeError.invalidResponse }
    }
}
