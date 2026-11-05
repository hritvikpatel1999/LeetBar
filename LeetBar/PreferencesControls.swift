import SwiftUI

struct PreferencesControls: View {
    @Binding var showStreak: Bool
    @Binding var showQuickLinks: Bool
    @Binding var showUpcomingContests: Bool
    @Binding var showTodaySection: Bool
    @Binding var showStudyPlans: Bool

    var body: some View {
        LeetBarToggleRow(title: "Show Quick Links", isOn: $showQuickLinks)
        LeetBarToggleRow(title: "Show Upcoming Contests", isOn: $showUpcomingContests)
        LeetBarToggleRow(title: "Show Today section", isOn: $showTodaySection)
        LeetBarToggleRow(title: "Show Study Plans", isOn: $showStudyPlans)
        LeetBarToggleRow(title: "Show streak count", isOn: $showStreak)
    }
}
