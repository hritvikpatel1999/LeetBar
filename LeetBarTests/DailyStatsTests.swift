import XCTest

final class DailyStatsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!
    }

    func testContestDayLabelsUseCalendarDays() {
        let locale = Locale(identifier: "en_US_POSIX")
        for (offset, expected) in [(0, "Today"), (1, "Tomorrow"), (2, "Thursday"), (4, "Saturday")] {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            XCTAssertEqual(
                ContestDayLabel.text(for: date, relativeTo: today, calendar: calendar, locale: locale), expected)
        }
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        let label = ContestDayLabel.text(for: nextWeek, relativeTo: today, calendar: calendar, locale: locale)
        XCTAssertTrue(label.contains("Oct"))
        XCTAssertTrue(label.contains("13"))
    }

    func testContestDayLabelRespectsLocalMidnight() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 17, minute: 30))!
        let contest = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 19))!
        var localCalendar = calendar
        localCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        XCTAssertEqual(ContestDayLabel.text(for: contest, relativeTo: now, calendar: calendar), "Today")
        XCTAssertEqual(ContestDayLabel.text(for: contest, relativeTo: now, calendar: localCalendar), "Tomorrow")
    }

    func testContestDayLabelHandlesDaylightSavingTransition() {
        var localCalendar = calendar
        localCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = localCalendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 45))!
        let contest = localCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23, minute: 15))!
        XCTAssertLessThan(contest.timeIntervalSince(now), 24 * 60 * 60)
        XCTAssertEqual(ContestDayLabel.text(for: contest, relativeTo: now, calendar: localCalendar), "Tomorrow")
    }

    func testCountsAllAttemptsButOnlyDistinctAcceptedProblems() {
        let submissions = [
            Submission(problemSlug: "two-sum", submittedAt: today, accepted: false),
            Submission(problemSlug: "two-sum", submittedAt: today, accepted: true),
            Submission(problemSlug: "two-sum", submittedAt: today, accepted: true),
            Submission(problemSlug: "valid-anagram", submittedAt: today, accepted: true),
            Submission(problemSlug: "valid-parentheses", submittedAt: today, accepted: false),
        ]

        XCTAssertEqual(
            DailyStats.calculate(submissions: submissions, on: today, calendar: calendar),
            DailyStats(submissions: 5, problemsSolved: 2)
        )
    }

    func testIncludesStartOfDayAndExcludesNextMidnight() {
        let start = calendar.startOfDay(for: today)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start)!
        let submissions = [
            Submission(problemSlug: "previous", submittedAt: start.addingTimeInterval(-1), accepted: true),
            Submission(problemSlug: "first", submittedAt: start, accepted: true),
            Submission(problemSlug: "last", submittedAt: nextDay.addingTimeInterval(-1), accepted: true),
            Submission(problemSlug: "next", submittedAt: nextDay, accepted: true),
        ]

        XCTAssertEqual(
            DailyStats.calculate(submissions: submissions, on: today, calendar: calendar),
            DailyStats(submissions: 2, problemsSolved: 2)
        )
    }

    func testUsesSelectedTimeZoneAcrossDaylightSavingBoundary() {
        var localCalendar = calendar
        localCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let localDate = localCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let start = localCalendar.startOfDay(for: localDate)
        let nextDay = localCalendar.date(byAdding: .day, value: 1, to: start)!
        let submissions = [
            Submission(problemSlug: "first", submittedAt: start, accepted: true),
            Submission(problemSlug: "last", submittedAt: nextDay.addingTimeInterval(-1), accepted: true),
            Submission(problemSlug: "next", submittedAt: nextDay, accepted: true),
        ]

        XCTAssertEqual(nextDay.timeIntervalSince(start), 23 * 60 * 60)
        XCTAssertEqual(
            DailyStats.calculate(submissions: submissions, on: localDate, calendar: localCalendar),
            DailyStats(submissions: 2, problemsSolved: 2)
        )
    }

    func testEmptyDayHasZeroCounts() {
        XCTAssertEqual(
            DailyStats.calculate(submissions: [], on: today, calendar: calendar),
            DailyStats(submissions: 0, problemsSolved: 0)
        )
    }

}
