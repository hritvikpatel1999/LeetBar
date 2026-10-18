import AppKit
import SwiftUI

@main
struct LeetBarApp: App {
    @AppStorage("showStreakInMenuBar") private var showStreak = true
    @AppStorage("showQuickLinks") private var showQuickLinks = true
    @AppStorage("showUpcomingContests") private var showUpcomingContests = true
    @AppStorage("showTodaySection") private var showTodaySection = true
    @AppStorage("showStudyPlans") private var showStudyPlans = true
    @StateObject private var account: AccountStore
    @StateObject private var quickLinks = QuickLinksStore()

    init() {
        let defaults = UserDefaults.standard
        _account = StateObject(wrappedValue: AccountStore(preferences: DashboardPreferences(
            showToday: defaults.object(forKey: "showTodaySection") as? Bool ?? true,
            showContests: defaults.object(forKey: "showUpcomingContests") as? Bool ?? true,
            showStudyPlans: defaults.object(forKey: "showStudyPlans") as? Bool ?? true)))
    }

    private var preferences: DashboardPreferences {
        DashboardPreferences(
            showToday: showTodaySection, showContests: showUpcomingContests, showStudyPlans: showStudyPlans)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(
                account: account, quickLinks: quickLinks, showQuickLinks: showQuickLinks,
                showUpcomingContests: showUpcomingContests, showTodaySection: showTodaySection,
                showStudyPlans: showStudyPlans
            )
            .onChange(of: preferences) { _, value in account.updatePreferences(value) }
        } label: {
            Image("LeetCodeMenuBar")
                .renderingMode(.template)
                .accessibilityLabel("LeetBar")
            if showStreak {
                Text(account.snapshot?.streak.map(String.init) ?? "--")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                showStreak: $showStreak, showQuickLinks: $showQuickLinks, showUpcomingContests: $showUpcomingContests,
                showTodaySection: $showTodaySection, showStudyPlans: $showStudyPlans, account: account,
                quickLinks: quickLinks
            )
            .onAppear {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .onChange(of: preferences) { _, value in account.updatePreferences(value) }
        }
    }
}
