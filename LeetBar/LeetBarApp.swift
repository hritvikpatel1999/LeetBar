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
    @StateObject private var quickLinks: QuickLinksStore
    @StateObject private var shortcut: GlobalShortcutStore
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
        let onboarding = OnboardingStore(account: account, logger: .shared)
        let quickLinks = QuickLinksStore()
        let shortcut = GlobalShortcutStore(logger: .shared)
        _account = StateObject(wrappedValue: account)
        _onboarding = StateObject(wrappedValue: onboarding)
        _quickLinks = StateObject(wrappedValue: quickLinks)
        _shortcut = StateObject(wrappedValue: shortcut)
        guard let image = NSImage(named: "LeetCodeMenuBar") else {
            preconditionFailure("LeetBar menu-bar image is missing.")
        }
        let delegate = appDelegate
        delegate.setMenuBarController(
            MenuBarController(
                account: account, shortcut: shortcut, image: image,
                bridge: AnyView(
                    ReopenSettingsBridge(
                        registerReopenAction: delegate.setReopenAction,
                        registerStartupAction: delegate.setStartupAction,
                        needsSetup: {
                            onboarding.prepare()
                            return !onboarding.isComplete
                        })),
                makeDashboard: {
                    AnyView(MenuBarDashboard(account: account, onboarding: onboarding, quickLinks: quickLinks))
                },
                onOpen: {
                    onboarding.prepare()
                    account.refreshIfNeeded()
                }))
    }

    private var preferences: DashboardPreferences {
        DashboardPreferences(
            showToday: showTodaySection, showContests: showUpcomingContests, showStudyPlans: showStudyPlans)
    }

    var body: some Scene {
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
                        quickLinks: quickLinks, launchAtLogin: launchAtLogin, diagnostics: diagnostics,
                        shortcutError: shortcut.errorMessage)
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
