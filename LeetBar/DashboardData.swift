import Foundation

enum SampleScenario: String, CaseIterable, Identifiable {
    case pending
    case completed
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: "Daily pending"
        case .completed: "Daily completed"
        case .unavailable: "Data unavailable"
        }
    }

    var completionText: String {
        switch self {
        case .pending: "Not completed"
        case .completed: "Completed"
        case .unavailable: "Unknown"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .pending: "curlybraces"
        case .completed: "checkmark.circle"
        case .unavailable: "questionmark.circle"
        }
    }

    var sampleStreak: Int? {
        switch self {
        case .pending: 7
        case .completed: 8
        case .unavailable: nil
        }
    }
}

struct Submission: Sendable {
    let problemSlug: String
    let submittedAt: Date
    let accepted: Bool
}

struct DailyStats: Equatable, Sendable {
    let submissions: Int
    let problemsSolved: Int

    static func calculate(
        submissions: [Submission],
        on date: Date,
        calendar: Calendar = .current
    ) -> DailyStats {
        let today = submissions.filter {
            calendar.isDate($0.submittedAt, inSameDayAs: date)
        }
        let solvedProblems = Set(today.filter(\.accepted).map(\.problemSlug))
        return DailyStats(submissions: today.count, problemsSolved: solvedProblems.count)
    }
}

enum ContestDayLabel {
    static func text(
        for date: Date,
        relativeTo now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            if let days, (2...6).contains(days) {
                formatter.setLocalizedDateFormatFromTemplate("EEEE")
            } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
                formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
            } else {
                formatter.setLocalizedDateFormatFromTemplate("EEE MMM d y")
            }
            return formatter.string(from: date)
        }
    }
}

struct DashboardData {
    let dailyTitle: String
    let dailyURL: URL
    let stats: DailyStats?
    let contestStart: Date

    static func sample(
        scenario: SampleScenario,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DashboardData {
        var submissions = [
            Submission(problemSlug: "valid-parentheses", submittedAt: now, accepted: false),
            Submission(problemSlug: "valid-parentheses", submittedAt: now, accepted: true),
            Submission(problemSlug: "valid-parentheses", submittedAt: now, accepted: true),
            Submission(problemSlug: "merge-two-sorted-lists", submittedAt: now, accepted: true),
            Submission(problemSlug: "valid-anagram", submittedAt: now, accepted: false),
            Submission(problemSlug: "valid-anagram", submittedAt: now, accepted: true),
            Submission(problemSlug: "two-sum", submittedAt: now, accepted: false),
        ]
        if scenario == .completed {
            submissions.append(
                Submission(problemSlug: "two-sum", submittedAt: now, accepted: true)
            )
        }

        return DashboardData(
            dailyTitle: "Two Sum",
            dailyURL: URL(string: "https://leetcode.com/problems/two-sum/")!,
            stats: scenario == .unavailable
                ? nil
                : DailyStats.calculate(
                    submissions: submissions, on: now, calendar: calendar
                ),
            contestStart: calendar.date(byAdding: .day, value: 2, to: now)!
        )
    }
}
