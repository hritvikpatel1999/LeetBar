import AppKit
import SwiftUI

@main
struct LeetBarApp: App {
    @AppStorage("sampleScenario") private var scenario: SampleScenario = .pending
    @AppStorage("showStreakInMenuBar") private var showStreak = true
    @AppStorage("useSampleData") private var useSampleData = false
    @StateObject private var account = AccountStore()
    @StateObject private var quickLinks = QuickLinksStore()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(scenario: scenario, useSampleData: useSampleData, account: account, quickLinks: quickLinks)
        } label: {
            Image("LeetCodeMenuBar")
                .renderingMode(.template)
                .accessibilityLabel("LeetBar")
            if showStreak {
                Text((useSampleData ? scenario.sampleStreak : account.snapshot?.streak).map(String.init) ?? "--")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                scenario: $scenario, showStreak: $showStreak, useSampleData: $useSampleData, account: account,
                quickLinks: quickLinks
            )
            .onAppear {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}
