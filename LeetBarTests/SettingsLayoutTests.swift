import AppKit
import ServiceManagement
import SwiftUI
import XCTest

@MainActor
final class SettingsLayoutTests: XCTestCase {
    func testEverySettingsPageKeepsWindowDimensionsInBothAppearances() throws {
        let suite = "LeetBarSettingsLayoutTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = AccountStore(storage: LayoutSessionStorage())
        let links = QuickLinksStore(defaults: defaults)
        let login = LaunchAtLoginStore(service: LayoutLoginService())
        let diagnostics = DiagnosticsStore(logger: .disabled, defaults: defaults)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for tab in SettingsTab.allCases {
                defaults.set(tab.rawValue, forKey: "settingsTab")
                let view = SettingsView(
                    showStreak: .constant(true), showQuickLinks: .constant(true),
                    showUpcomingContests: .constant(true), showTodaySection: .constant(true),
                    showStudyPlans: .constant(true), account: account, quickLinks: links,
                    launchAtLogin: login, diagnostics: diagnostics, logger: .disabled
                )
                .defaultAppStorage(defaults)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: appearance)
                XCTAssertEqual(host.fittingSize, NSSize(width: 500, height: 500), tab.rawValue)
                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: host.fittingSize),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(defaults.string(forKey: "settingsTab"), tab.rawValue)
            }
        }
    }

    func testSharedCredentialFieldsFitInsideCardWidth() {
        let fields = LeetCodeCredentialFields(
            sessionCookie: .constant(""), csrfToken: .constant(""), identifierPrefix: "onboarding")
        let host = NSHostingView(rootView: fields.frame(width: 368))
        XCTAssertGreaterThan(host.fittingSize.height, 100)
        XCTAssertEqual(host.fittingSize.width, 368)
    }

    func testSelectingNativeTabsPersistsDestination() async throws {
        let suite = "LeetBarSettingsNavigationTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(SettingsTab.preferences.rawValue, forKey: "settingsTab")
        let host = NSHostingView(
            rootView: SettingsTabBarTestRoot()
                .defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let tabs = findButtons(in: host)
        XCTAssertEqual(tabs.count, 5)
        XCTAssertEqual(tabs.map(\.title), SettingsTab.allCases.map(\.title))
        for (index, tab) in SettingsTab.allCases.enumerated() {
            tabs[index].performClick(nil)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(defaults.string(forKey: "settingsTab"), tab.rawValue)
            XCTAssertEqual(tabs[index].accessibilityValue() as? String, "Selected")
        }
    }

    func testLeetBarTitleStaysVisibleAcrossPagesWithCenteredPreferencesToolbar() async throws {
        let suite = "LeetBarSettingsTitleTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(SettingsTab.preferences.rawValue, forKey: "settingsTab")
        let account = AccountStore(storage: LayoutSessionStorage())
        let host = NSHostingView(
            rootView: SettingsView(
                showStreak: .constant(true), showQuickLinks: .constant(true),
                showUpcomingContests: .constant(true), showTodaySection: .constant(true),
                showStudyPlans: .constant(true), account: account, quickLinks: QuickLinksStore(defaults: defaults),
                launchAtLogin: LaunchAtLoginStore(service: LayoutLoginService()),
                diagnostics: DiagnosticsStore(logger: .disabled, defaults: defaults), logger: .disabled
            )
            .leetBarAppearance().defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Diagnostics"
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertEqual(window.title, "LeetBar")
        for tab in [SettingsTab.appearance, .quickLinks, .account, .diagnostics, .preferences] {
            window.titleVisibility = .hidden
            defaults.set(tab.rawValue, forKey: "settingsTab")
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(window.titleVisibility, .visible, tab.rawValue)
            XCTAssertEqual(window.title, "LeetBar", tab.rawValue)
            XCTAssertEqual(window.toolbarStyle, .preference)
            XCTAssertNotNil(window.standardWindowButton(.closeButton))
            XCTAssertTrue(window.styleMask.contains(.titled))
            let toolbar = try XCTUnwrap(window.toolbar)
            let buttons = toolbar.items.compactMap(\.view).flatMap { findButtons(in: $0) }
            XCTAssertEqual(buttons.count, 5)
            let first = try XCTUnwrap(buttons.first)
            let last = try XCTUnwrap(buttons.last)
            let firstFrame = window.convertToScreen(first.convert(first.bounds, to: nil))
            let lastFrame = window.convertToScreen(last.convert(last.bounds, to: nil))
            XCTAssertEqual((firstFrame.minX + lastFrame.maxX) / 2, window.frame.midX, accuracy: 1)
            for button in buttons {
                let cell = try XCTUnwrap(button.cell)
                let image = cell.imageRect(forBounds: button.bounds)
                let title = cell.titleRect(forBounds: button.bounds)
                XCTAssertFalse(image.intersects(title), "Navigation icons and labels must not overlap.")
                XCTAssertGreaterThanOrEqual(image.minY, button.bounds.minY + 4)
                XCTAssertLessThanOrEqual(image.maxY, button.bounds.maxY - 4)
                XCTAssertGreaterThanOrEqual(title.minY, button.bounds.minY + 4)
                XCTAssertGreaterThanOrEqual(image.minX, button.bounds.minX)
                XCTAssertLessThanOrEqual(image.maxX, button.bounds.maxX)
                XCTAssertGreaterThanOrEqual(title.minX, button.bounds.minX)
                XCTAssertLessThanOrEqual(title.maxX, button.bounds.maxX)
            }
            window.title = tab.title
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(window.title, "LeetBar", "Restore the app title after a native tab-title update.")
        }
    }

    private func findButtons(in view: NSView) -> [NSButton] {
        if let button = view as? NSButton { return [button] }
        return view.subviews.flatMap { findButtons(in: $0) }
    }
}

private struct SettingsTabBarTestRoot: View {
    @AppStorage("settingsTab") private var selection: SettingsTab = .preferences

    var body: some View {
        SettingsTabBar(selection: $selection, theme: .sunset)
            .frame(width: 400, height: 58)
    }
}

private struct LayoutSessionStorage: SessionStoring {
    func load() throws -> LeetCodeSession? { nil }
    func save(_ session: LeetCodeSession) throws {}
    func delete() throws {}
}

@MainActor
private struct LayoutLoginService: LoginItemServing {
    var status: SMAppService.Status { .notRegistered }
    func register() throws {}
    func unregister() async throws {}
    func openSystemSettings() {}
}
