import AppKit
import SwiftUI

@main
struct LeetBarApp: App {
    @NSApplicationDelegateAdaptor(DiagnosticsAppDelegate.self) private var appDelegate
    @AppStorage("showStreakInMenuBar") private var showStreak = true
    @AppStorage("showQuickLinks") private var showQuickLinks = true
    @AppStorage("showUpcomingContests") private var showUpcomingContests = true
    @AppStorage("showTodaySection") private var showTodaySection = true
    @AppStorage("showStudyPlans") private var showStudyPlans = true
    @StateObject private var account: AccountStore
    @StateObject private var onboarding: OnboardingStore
    @StateObject private var quickLinks = QuickLinksStore()
    @StateObject private var launchAtLogin = LaunchAtLoginStore(logger: .shared)
    @StateObject private var diagnostics = DiagnosticsStore()

    init() {
        let defaults = UserDefaults.standard
        let account = AccountStore(
            client: LeetCodeClient(logger: .shared),
            preferences: DashboardPreferences(
                showToday: defaults.object(forKey: "showTodaySection") as? Bool ?? true,
                showContests: defaults.object(forKey: "showUpcomingContests") as? Bool ?? true,
                showStudyPlans: defaults.object(forKey: "showStudyPlans") as? Bool ?? true), logger: .shared)
        _account = StateObject(wrappedValue: account)
        _onboarding = StateObject(wrappedValue: OnboardingStore(account: account, logger: .shared))
    }

    private var preferences: DashboardPreferences {
        DashboardPreferences(
            showToday: showTodaySection, showContests: showUpcomingContests, showStudyPlans: showStudyPlans)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(
                account: account, onboarding: onboarding, quickLinks: quickLinks, showQuickLinks: showQuickLinks,
                showUpcomingContests: showUpcomingContests, showTodaySection: showTodaySection,
                showStudyPlans: showStudyPlans
            )
            .leetBarAppearance()
            .onChange(of: preferences) { _, value in account.updatePreferences(value) }
        } label: {
            HStack {
                Image("LeetCodeMenuBar")
                    .renderingMode(.template)
                    .accessibilityLabel("LeetBar")
                if showStreak {
                    Text(account.snapshot?.streak.map(String.init) ?? "--")
                }
            }
            .background {
                ReopenSettingsBridge(
                    registerReopenAction: appDelegate.setReopenAction,
                    registerStartupAction: appDelegate.setStartupAction,
                    needsSetup: {
                        onboarding.prepare()
                        return !onboarding.isComplete
                    }
                ).frame(width: 0, height: 0)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            Group {
                if !onboarding.isPrepared {
                    ProgressView().frame(width: 500, height: 500)
                } else if !onboarding.isComplete {
                    OnboardingView(
                        onboarding: onboarding, account: account, showStreak: $showStreak,
                        showQuickLinks: $showQuickLinks, showUpcomingContests: $showUpcomingContests,
                        showTodaySection: $showTodaySection, showStudyPlans: $showStudyPlans)
                } else {
                    SettingsView(
                        showStreak: $showStreak, showQuickLinks: $showQuickLinks,
                        showUpcomingContests: $showUpcomingContests,
                        showTodaySection: $showTodaySection, showStudyPlans: $showStudyPlans, account: account,
                        quickLinks: quickLinks, launchAtLogin: launchAtLogin, diagnostics: diagnostics)
                }
            }
            .leetBarAppearance()
            .task { onboarding.prepare() }
            .onAppear {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .onChange(of: preferences) { _, value in account.updatePreferences(value) }
        }
    }
}
