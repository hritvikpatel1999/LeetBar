import AppKit
import SwiftUI
import XCTest

@MainActor
final class ThemeTests: XCTestCase {
    func testFourNamedThemesAndDefault() {
        XCTAssertEqual(AppTheme.allCases.map(\.title), ["Teal", "Ocean", "Violet", "Sunset"])
        XCTAssertEqual(EnvironmentValues().leetBarTheme, .teal)
    }

    func testThemePickerClearsInitialFocusButPreservesSubsequentKeyboardNavigation() async throws {
        let suite = "LeetBarThemeFocusTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = NSHostingView(
            rootView: LeetBarThemePicker().padding(24).frame(width: 400)
                .leetBarAppearance().defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 140),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let initialResponder = try XCTUnwrap(window.initialFirstResponder)
        XCTAssertTrue(window.firstResponder === initialResponder, "Do not automatically focus the first theme.")
        XCTAssertNil(defaults.string(forKey: AppTheme.storageKey), "Focus must not change the saved theme.")

        window.orderOut(nil)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(
            window.firstResponder === initialResponder, "Reopening should keep the same unfocused appearance.")

        window.selectNextKeyView(nil)
        try await Task.sleep(for: .milliseconds(50))
        let keyboardResponder = try XCTUnwrap(window.firstResponder)
        XCTAssertFalse(keyboardResponder === initialResponder, "Theme controls must remain reachable by keyboard.")
        XCTAssertFalse(keyboardResponder === window, "Tab should move into a control, not leave focus on the window.")
        defaults.set(AppTheme.sunset.rawValue, forKey: AppTheme.storageKey)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(window.firstResponder === keyboardResponder, "Theme updates must not steal keyboard focus.")
    }

    func testNativeNavigationTextAndIconsFollowLiveThemeInBothAppearances() async throws {
        let suite = "LeetBarNavigationThemeTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(SettingsTab.appearance.rawValue, forKey: "settingsTab")
        let host = NSHostingView(
            rootView: ThemeTabBarProbe().leetBarAppearance().defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 58),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let buttons = nativeButtons(in: host)
        XCTAssertEqual(buttons.count, 5)
        let selected = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "appearance" })
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            host.appearance = NSAppearance(named: appearance)
            for theme in AppTheme.allCases {
                defaults.set(theme.rawValue, forKey: AppTheme.storageKey)
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(selected.contentTintColor, NSColor(theme.accent))
                for button in buttons where button !== selected {
                    XCTAssertEqual(button.contentTintColor, .secondaryLabelColor)
                }
                let bitmap = try XCTUnwrap(selected.bitmapImageRepForCachingDisplay(in: selected.bounds))
                var resolvedColor: NSColor?
                host.effectiveAppearance.performAsCurrentDrawingAppearance {
                    resolvedColor = NSColor(theme.accent).usingColorSpace(.deviceRGB)
                    selected.cacheDisplay(in: selected.bounds, to: bitmap)
                }
                let expected = try XCTUnwrap(resolvedColor)
                let centerX = bitmap.pixelsWide / 2
                let scale = CGFloat(bitmap.pixelsHigh) / selected.bounds.height
                for edgeRow in [0, Int(6 * scale), bitmap.pixelsHigh - 1, bitmap.pixelsHigh - 1 - Int(2 * scale)] {
                    XCTAssertLessThan(
                        try XCTUnwrap(bitmap.colorAt(x: centerX, y: edgeRow)).alphaComponent, 0.02,
                        "Leave a clear gap above and below the highlight.")
                }
                for insetRow in [Int(8 * scale), bitmap.pixelsHigh - 1 - Int(4 * scale)] {
                    XCTAssertGreaterThan(
                        try XCTUnwrap(bitmap.colorAt(x: centerX, y: insetRow)).alphaComponent, 0.08,
                        "Keep the highlight inside the unchanged button bounds.")
                }
                var expectedHue: CGFloat = 0
                expected.getHue(&expectedHue, saturation: nil, brightness: nil, alpha: nil)
                var topPixels = 0
                var bottomPixels = 0
                var firstContentRow = bitmap.pixelsHigh
                var lastContentRow = -1
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        var hue: CGFloat = 0
                        var saturation: CGFloat = 0
                        color.getHue(&hue, saturation: &saturation, brightness: nil, alpha: nil)
                        let difference = abs(hue - expectedHue)
                        if color.alphaComponent > 0.8 && saturation > 0.25 && min(difference, 1 - difference) < 0.045 {
                            firstContentRow = min(firstContentRow, y)
                            lastContentRow = max(lastContentRow, y)
                            if y < bitmap.pixelsHigh / 2 { topPixels += 1 } else { bottomPixels += 1 }
                        }
                    }
                }
                XCTAssertGreaterThan(topPixels, 5, "\(theme), \(appearance): icon must use the theme color.")
                XCTAssertGreaterThan(bottomPixels, 5, "\(theme), \(appearance): text must use the theme color.")
                let bottomPadding = bitmap.pixelsHigh - 1 - lastContentRow
                XCTAssertGreaterThanOrEqual(firstContentRow, 8, "The icon needs visible padding above it.")
                XCTAssertGreaterThanOrEqual(bottomPadding, 8, "The caption must stay clear of the highlight edge.")
                XCTAssertEqual(
                    CGFloat(firstContentRow - bottomPadding) / scale, 3, accuracy: 1,
                    "The icon-only offset intentionally adds top space without moving the caption.")
            }
        }
    }

    private func nativeButtons(in view: NSView) -> [NSButton] {
        if let button = view as? NSButton { return [button] }
        return view.subviews.flatMap { nativeButtons(in: $0) }
    }

    func testSavedThemeRestoresAndUpdatesMultipleSurfacesLive() async throws {
        let suite = "LeetBarThemeTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "showStudyPlans")
        defaults.set("credentials", forKey: OnboardingStore.stepKey)
        var first: AppTheme?
        var second: AppTheme?
        let hosts = [
            NSHostingView(rootView: ThemeProbe { first = $0 }.leetBarAppearance().defaultAppStorage(defaults)),
            NSHostingView(rootView: ThemeProbe { second = $0 }.leetBarAppearance().defaultAppStorage(defaults)),
        ]
        let windows = hosts.map { host in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
            return window
        }
        defer { windows.forEach { $0.orderOut(nil) } }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(first, .teal)
        XCTAssertEqual(second, .teal)
        for theme in AppTheme.allCases {
            defaults.set(theme.rawValue, forKey: AppTheme.storageKey)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(first, theme)
            XCTAssertEqual(second, theme)
            var restored: AppTheme?
            let fresh = NSHostingView(
                rootView: ThemeProbe { restored = $0 }.leetBarAppearance().defaultAppStorage(defaults))
            windows[0].contentView = fresh
            fresh.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(restored, theme)
            windows[0].contentView = hosts[0]
        }
        XCTAssertFalse(defaults.bool(forKey: "showStudyPlans"))
        XCTAssertEqual(defaults.string(forKey: OnboardingStore.stepKey), "credentials")
    }

    func testEveryThemeProducesDistinctAdaptiveWindowAndCardSurfaces() throws {
        for isCard in [false, true] {
            for scheme in [ColorScheme.light, .dark] {
                var colors: [NSColor] = []
                for theme in AppTheme.allCases {
                    let host = NSHostingView(
                        rootView: LeetBarSurface(isCard: isCard)
                            .environment(\.leetBarTheme, theme)
                            .environment(\.colorScheme, scheme)
                            .frame(width: 40, height: 40))
                    host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                    let window = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                        styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    colors.append(try XCTUnwrap(bitmap.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB)))
                }
                for i in colors.indices {
                    for j in colors.indices where j > i {
                        let difference =
                            abs(colors[i].redComponent - colors[j].redComponent)
                            + abs(colors[i].greenComponent - colors[j].greenComponent)
                            + abs(colors[i].blueComponent - colors[j].blueComponent)
                        XCTAssertGreaterThan(difference, 0.005, "\(isCard), \(scheme), \(i), \(j)")
                    }
                }
            }
        }
    }

    func testChangingThemeDoesNotRefetchDashboardData() async throws {
        let suite = "LeetBarDashboardThemeTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ThemeAccountService()
        let account = AccountStore(storage: ThemeSessionStorage(), client: service)
        account.restore()
        let work = try XCTUnwrap(
            account.connect(LeetCodeSession(sessionCookie: "demo", csrfToken: "demo-csrf")))
        await work.value
        let onboarding = OnboardingStore(account: account, defaults: defaults)
        let host = NSHostingView(
            rootView: DashboardView(
                account: account, onboarding: onboarding,
                quickLinks: QuickLinksStore(defaults: defaults),
                showQuickLinks: true, showUpcomingContests: true, showTodaySection: true,
                showStudyPlans: true
            )
            .leetBarAppearance().defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let baseline = await service.requests
        XCTAssertEqual(baseline, 2)
        for theme in AppTheme.allCases {
            defaults.set(theme.rawValue, forKey: AppTheme.storageKey)
            try await Task.sleep(for: .milliseconds(50))
            let requests = await service.requests
            XCTAssertEqual(requests, baseline)
        }
    }
}

private struct ThemeTabBarProbe: View {
    @Environment(\.leetBarTheme) private var theme
    @AppStorage("settingsTab") private var selection: SettingsTab = .preferences

    var body: some View {
        SettingsTabBar(selection: $selection, theme: theme).frame(width: 400, height: 58)
    }
}

private struct ThemeProbe: View {
    @Environment(\.leetBarTheme) private var theme
    let report: (AppTheme) -> Void

    var body: some View {
        Color.clear.frame(width: 40, height: 40)
            .onAppear { report(theme) }
            .onChange(of: theme) { _, value in report(value) }
    }
}

private struct ThemeSessionStorage: SessionStoring {
    func load() throws -> LeetCodeSession? { nil }
    func save(_ session: LeetCodeSession) throws {}
    func delete() throws {}
}

private actor ThemeAccountService: LeetCodeServing {
    private(set) var requests = 0

    func account(session: LeetCodeSession) async throws -> LeetCodeAccount {
        requests += 1
        return LeetCodeAccount(isSignedIn: true, username: "theme-demo")
    }

    func dashboard(
        session: LeetCodeSession, username: String, now: Date, calendar: Calendar,
        sections: Set<DashboardSection>
    ) async throws -> LiveDashboard {
        requests += 1
        return LiveDashboard(
            daily: nil, stats: nil, contests: [], studyPlans: [], streak: nil,
            contestRating: nil, checkedAt: now, sectionIssues: [:])
    }
}
