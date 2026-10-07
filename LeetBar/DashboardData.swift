import Foundation

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
