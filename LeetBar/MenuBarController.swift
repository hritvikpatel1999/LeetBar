import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private(set) var statusItem: NSStatusItem?
    let popover: NSPopover
    private let account: AccountStore
    private let defaults: UserDefaults
    private let shortcut: GlobalShortcutStore
    private let image: NSImage
    private let bridge: AnyView
    private let makeDashboard: @MainActor () -> AnyView
    private let onOpen: @MainActor () -> Void
    private var subscriptions: Set<AnyCancellable> = []
    private var bridgeHost: NSHostingView<AnyView>?

    init(
        account: AccountStore, defaults: UserDefaults = .standard, shortcut: GlobalShortcutStore,
        image: NSImage, bridge: AnyView, popover: NSPopover = NSPopover(),
        makeDashboard: @escaping @MainActor () -> AnyView,
        onOpen: @escaping @MainActor () -> Void
    ) {
        self.account = account
        self.defaults = defaults
        self.shortcut = shortcut
        self.image = image
        self.bridge = bridge
        self.popover = popover
        self.makeDashboard = makeDashboard
        self.onOpen = onOpen
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    func start() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { preconditionFailure("LeetBar status button is unavailable.") }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        button.image = image
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(toggleDashboard)
        button.toolTip = "LeetBar — Command-Option-L"
        button.setAccessibilityLabel("LeetBar")
        let host = NSHostingView(rootView: bridge)
        host.frame = .zero
        button.addSubview(host)
        bridgeHost = host
        host.layoutSubtreeIfNeeded()
        account.$snapshot.sink { [weak self] snapshot in self?.updateLabel(streak: snapshot?.streak) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateLabel(streak: self.account.snapshot?.streak)
            }
            .store(in: &subscriptions)
        updateLabel(streak: account.snapshot?.streak)
        shortcut.start { [weak self] in self?.toggleDashboard() }
    }

    @objc func toggleDashboard() {
        if popover.isShown {
            closeDashboard()
            return
        }
        guard let button = statusItem?.button else { return }
        onOpen()
        if popover.contentViewController == nil {
            let controller = NSHostingController(
                rootView: makeDashboard().onExitCommand { [weak self] in
                    self?.closeDashboard()
                })
            controller.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
            popover.contentViewController = controller
            controller.view.layoutSubtreeIfNeeded()
            popover.contentSize = controller.view.fittingSize
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
    }

    func closeDashboard() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
    }

    func stop() {
        shortcut.stop()
        closeDashboard()
        subscriptions.removeAll()
        bridgeHost?.removeFromSuperview()
        bridgeHost = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func updateLabel(streak: Int?) {
        let showStreak = defaults.object(forKey: "showStreakInMenuBar") as? Bool ?? true
        statusItem?.button?.title = showStreak ? " \(streak.map(String.init) ?? "--")" : ""
    }
}

struct MenuBarDashboard: View {
    @ObservedObject var account: AccountStore
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var quickLinks: QuickLinksStore
    @AppStorage("showQuickLinks") private var showQuickLinks = true
    @AppStorage("showUpcomingContests") private var showUpcomingContests = true
    @AppStorage("showTodaySection") private var showTodaySection = true
    @AppStorage("showStudyPlans") private var showStudyPlans = true

    private var preferences: DashboardPreferences {
        DashboardPreferences(
            showToday: showTodaySection, showContests: showUpcomingContests, showStudyPlans: showStudyPlans)
    }

    var body: some View {
        DashboardView(
            account: account, onboarding: onboarding, quickLinks: quickLinks,
            showQuickLinks: showQuickLinks, showUpcomingContests: showUpcomingContests,
            showTodaySection: showTodaySection, showStudyPlans: showStudyPlans
        )
        .leetBarAppearance()
        .onChange(of: preferences) { _, value in account.updatePreferences(value) }
    }
}
