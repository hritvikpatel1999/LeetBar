import AppKit
import SwiftUI
import XCTest

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testStartRegistersOnceAndHiddenBridgeIsReadyBeforeDashboardOpens() throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.controller.start()
        fixture.controller.start()
        XCTAssertTrue(fixture.bridgeRegistered)
        XCTAssertEqual(fixture.registrar.registrations, 1)
        XCTAssertNotNil(fixture.controller.statusItem)
        XCTAssertFalse(fixture.controller.popover.isShown)
        XCTAssertNil(fixture.controller.popover.contentViewController)
        XCTAssertEqual(fixture.opens, 0)
        XCTAssertEqual(fixture.controller.statusItem?.button?.image?.isTemplate, true)
        XCTAssertEqual(fixture.controller.statusItem?.button?.title, " --")
    }

    func testShortcutAndButtonShareToggleWithLazyDashboardAndCleanup() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.controller.start()
        try await Task.sleep(for: .milliseconds(50))
        fixture.registrar.action?()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(fixture.controller.popover.isShown)
        XCTAssertEqual(fixture.opens, 1)
        let hosted = try XCTUnwrap(fixture.controller.popover.contentViewController)
        fixture.controller.toggleDashboard()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(fixture.controller.popover.isShown)
        fixture.controller.statusItem?.button?.performClick(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(fixture.controller.popover.isShown)
        XCTAssertEqual(fixture.opens, 2)
        XCTAssertTrue(fixture.controller.popover.contentViewController === hosted)
        fixture.controller.stop()
        XCTAssertFalse(fixture.controller.popover.isShown)
        XCTAssertNil(fixture.controller.statusItem)
        XCTAssertNil(fixture.registrar.action)
        XCTAssertEqual(fixture.registrar.unregistrations, 1)
    }

    func testStreakPreferenceUpdatesNativeLabelWithoutDashboardCreation() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.controller.start()
        fixture.defaults.set(false, forKey: "showStreakInMenuBar")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fixture.controller.statusItem?.button?.title, "")
        fixture.defaults.set(true, forKey: "showStreakInMenuBar")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fixture.controller.statusItem?.button?.title, " --")
        XCTAssertNil(fixture.controller.popover.contentViewController)
        XCTAssertEqual(fixture.opens, 0)
    }

    func testShortcutFailureDoesNotRemoveClickableStatusItem() async throws {
        let fixture = try Fixture()
        defer { fixture.stop() }
        fixture.registrar.failure = GlobalShortcutError(status: -9878)
        fixture.controller.start()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(fixture.shortcut.errorMessage)
        fixture.controller.toggleDashboard()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(fixture.controller.popover.isShown)
    }

    @MainActor
    private final class Fixture {
        let suite = "LeetBarMenuBarTests-\(UUID())"
        let defaults: UserDefaults
        let registrar = ShortcutRegistrarFake()
        let shortcut: GlobalShortcutStore
        let popover = TestPopover()
        var controller: MenuBarController!
        var bridgeRegistered = false
        var opens = 0

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            shortcut = GlobalShortcutStore(registrar: registrar)
            controller = MenuBarController(
                account: AccountStore(), defaults: defaults, shortcut: shortcut,
                image: NSImage(size: NSSize(width: 18, height: 18)),
                bridge: AnyView(
                    ReopenSettingsBridge(registerReopenAction: { [weak self] _ in
                        self?.bridgeRegistered = true
                    })),
                popover: popover,
                makeDashboard: { AnyView(Text("Dashboard").frame(width: 360, height: 200)) },
                onOpen: { [weak self] in self?.opens += 1 })
            XCTAssertEqual(controller.popover.behavior, .transient)
        }

        func stop() {
            controller.stop()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @MainActor
    private final class TestPopover: NSPopover {
        private var testIsVisible = false
        override var isShown: Bool { testIsVisible }

        override func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
            testIsVisible = true
        }

        override func performClose(_ sender: Any?) {
            testIsVisible = false
            delegate?.popoverDidClose?(Notification(name: NSPopover.didCloseNotification, object: self))
        }
    }
}
