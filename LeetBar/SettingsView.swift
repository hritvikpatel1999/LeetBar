import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case preferences, appearance, quickLinks, account, diagnostics

    var title: String {
        switch self {
        case .preferences: "Preferences"
        case .appearance: "Appearance"
        case .quickLinks: "Quick Links"
        case .account: "Account"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .preferences: "slider.horizontal.3"
        case .appearance: "paintpalette"
        case .quickLinks: "link"
        case .account: "person.crop.circle"
        case .diagnostics: "waveform.path"
        }
    }

    var subtitle: String {
        switch self {
        case .preferences: "A little less clutter. A little more you."
        case .appearance: "A little color. All your own."
        case .quickLinks: "Your favorite practice spots, one click away."
        case .account: "Your LeetCode connection, safely on your Mac."
        case .diagnostics: "A little insight when things don't go to plan."
        }
    }
}

struct SettingsTabBar: NSViewRepresentable {
    @Binding var selection: SettingsTab
    let theme: AppTheme

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        for tab in SettingsTab.allCases {
            let button = NSButton(frame: .zero)
            button.cell = TabButtonCell(textCell: tab.title)
            button.target = context.coordinator
            button.action = #selector(Coordinator.selectTab(_:))
            button.identifier = NSUserInterfaceItemIdentifier(tab.rawValue)
            button.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 23, weight: .regular))
            button.imagePosition = .imageAbove
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.imageScaling = .scaleProportionallyDown
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.setAccessibilityLabel(tab.title)
            button.wantsLayer = true
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 80).isActive = true
            button.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        context.coordinator.selection = $selection
        for (view, tab) in zip(stack.arrangedSubviews, SettingsTab.allCases) {
            guard let button = view as? NSButton else { preconditionFailure("Settings tabs must be native buttons.") }
            let isSelected = selection == tab
            button.contentTintColor = isSelected ? NSColor(theme.accent) : .secondaryLabelColor
            guard let cell = button.cell as? TabButtonCell else { preconditionFailure("Settings tab cell missing.") }
            cell.highlightColor = isSelected ? NSColor(theme.accent).withAlphaComponent(0.12) : nil
            button.needsDisplay = true
            button.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        }
    }

    final class TabButtonCell: NSButtonCell {
        var highlightColor: NSColor?

        override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
            if let highlightColor {
                highlightColor.setFill()
                var highlightFrame = cellFrame.insetBy(dx: 0, dy: 3)
                highlightFrame.size.height -= 4
                if controlView.isFlipped { highlightFrame.origin.y += 4 }
                NSBezierPath(roundedRect: highlightFrame, xRadius: 9, yRadius: 9).fill()
            }
            super.draw(withFrame: cellFrame, in: controlView)
        }

        override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
            // Image-above cells otherwise leave more space below the caption than above the icon.
            let frame = cellFrame.offsetBy(dx: 0, dy: controlView.isFlipped ? 6 : -6)
            super.drawInterior(withFrame: frame, in: controlView)
        }

        override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect
        {
            super.drawTitle(
                title, withFrame: frame.offsetBy(dx: 0, dy: controlView.isFlipped ? -2 : 2), in: controlView)
        }

        override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
            super.drawImage(
                image, withFrame: frame.offsetBy(dx: 0, dy: controlView.isFlipped ? 4 : -4), in: controlView)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<SettingsTab>

        init(selection: Binding<SettingsTab>) {
            self.selection = selection
        }

        @objc func selectTab(_ sender: NSButton) {
            guard let identifier = sender.identifier, let tab = SettingsTab(rawValue: identifier.rawValue) else {
                preconditionFailure("Unknown Settings tab.")
            }
            selection.wrappedValue = tab
        }
    }
}

struct SettingsView: View {
    @Binding var showStreak: Bool
    @Binding var showQuickLinks: Bool
    @Binding var showUpcomingContests: Bool
    @Binding var showTodaySection: Bool
    @Binding var showStudyPlans: Bool
    @ObservedObject var account: AccountStore
    @ObservedObject var quickLinks: QuickLinksStore
    @ObservedObject var launchAtLogin: LaunchAtLoginStore
    @ObservedObject var diagnostics: DiagnosticsStore
    var shortcutError: String?
    var logger: DiagnosticLogger = .shared
    @AppStorage("settingsTab") private var selectedTab: SettingsTab = .preferences
    @Environment(\.leetBarTheme) private var theme
    @State private var sessionCookie = ""
    @State private var csrfToken = ""
    @State private var validationMessage: String?
    @State private var isReconnecting = false
    @State private var quickLinkEditor: QuickLinkEditorRequest?
    @State private var quickLinksMessage: String?
    @State private var isResettingQuickLinks = false
    @State private var isClearingLogs = false

    private var showsConnectionForm: Bool {
        isReconnecting || !account.hasSavedSession || account.connectionPhase == .failed
            || (account.isWorking && account.connectionPhase.statusMessage != nil)
    }

    private var accountStatus: String {
        if account.connectionPhase == .failed { return "Connection needs attention" }
        if !account.hasSavedSession { return "Not connected" }
        return account.username == nil ? "Session saved" : "Connected to LeetCode"
    }

    var body: some View {
        page(selectedTab)
            .id(selectedTab)
            .toolbar {
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .principal) { navigationButtons }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) { navigationButtons }
                }
            }
            .frame(width: 500, height: 500)
            .background { SettingsWindowTitle().id(selectedTab).frame(width: 0, height: 0) }
            .sheet(item: $quickLinkEditor) { request in
                QuickLinkEditor(store: quickLinks, original: request.link)
            }
            .alert("Reset Quick Links?", isPresented: $isResettingQuickLinks) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { quickLinks.reset() }
            } message: {
                Text("The saved quick-link data will be removed. Your LeetCode connection will not change.")
            }
            .alert("Clear Logs?", isPresented: $isClearingLogs) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { Task { await diagnostics.clear() } }
            } message: {
                Text(
                    "Existing diagnostic entries will be deleted. Current startup metadata will remain. Your account and preferences will not change."
                )
            }
            .task {
                account.restore()
                launchAtLogin.refresh()
                diagnostics.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                launchAtLogin.refresh()
                diagnostics.refresh()
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                if selectedTab == .diagnostics { diagnostics.refresh() }
            }
            .onChange(of: selectedTab) { _, tab in
                if tab != .account {
                    clearCredentialDrafts()
                    isReconnecting = false
                }
                if tab == .diagnostics { diagnostics.refresh() }
            }
            .onChange(of: account.connectionPhase) { _, phase in
                if phase == .connected {
                    isReconnecting = false
                    clearCredentialDrafts()
                }
            }
            .onDisappear { clearCredentialDrafts() }
    }

    private var navigationButtons: some View {
        SettingsTabBar(selection: $selectedTab, theme: theme)
            .frame(width: 400, height: 58)
            .padding(.vertical, 4)
    }

    private func page(_ tab: SettingsTab) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                LeetBarPageHeader(title: tab.title, subtitle: tab.subtitle)
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .preferences: preferencesPage
                    case .appearance: appearancePage
                    case .quickLinks: quickLinksPage
                    case .account: accountPage
                    case .diagnostics: diagnosticsPage
                    }
                }
            }
            .frame(maxWidth: LeetBarStyle.contentWidth)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { LeetBarSurface() }
        .accessibilityIdentifier("settings-\(tab.rawValue)")
    }

    private var appearancePage: some View {
        Group {
            LeetBarCard {
                Text("Color theme").font(.headline)
                LeetBarThemePicker()
                Text(
                    "Shared across your menu-bar dashboard, Settings, and setup. Light and dark appearance follow macOS."
                )
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            LeetBarCard {
                HStack {
                    Label("Dashboard preview", systemImage: "menubar.rectangle")
                        .font(.headline)
                    Spacer()
                    Text(theme.title).font(.caption).foregroundStyle(theme.accent)
                }
                Divider()
                HStack {
                    Label("Daily Problem", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(theme.accent)
                }
                Text("Your next solve starts here.").font(.subheadline.weight(.semibold))
                ProgressView(value: 0.65)
                    .accessibilityLabel("Sample study-plan progress")
                Text("Sample content. Your theme updates everywhere instantly.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var preferencesPage: some View {
        Group {
            LeetBarCard {
                Text("In your menu bar").font(.headline)
                PreferencesControls(
                    showStreak: $showStreak, showQuickLinks: $showQuickLinks,
                    showUpcomingContests: $showUpcomingContests, showTodaySection: $showTodaySection,
                    showStudyPlans: $showStudyPlans)
            }
            LeetBarCard {
                HStack {
                    Text("Open dashboard").font(.headline)
                    Spacer()
                    Text("⌘⌥L").font(.headline.monospaced())
                }
                Text("Press Command-Option-L from any app to open or close LeetBar. Press Escape to dismiss it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let shortcutError { errorText(shortcutError) }
            }
            LeetBarCard {
                LeetBarToggleRow(
                    title: "Launch at login",
                    isOn: Binding(
                        get: { launchAtLogin.isOn },
                        set: { enabled in Task { await launchAtLogin.setEnabled(enabled) } })
                )
                .disabled(!launchAtLogin.canToggle)
                .help("Enable this from your installed copy in Applications, not a temporary development build.")
                Text(launchAtLogin.statusMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if launchAtLogin.isWorking { ProgressView().controlSize(.small) }
                if let error = launchAtLogin.errorMessage { errorText(error) }
                Button("Manage Login Items in System Settings") { launchAtLogin.openSystemSettings() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var quickLinksPage: some View {
        Group {
            HStack {
                Text("\(quickLinks.links.count) of \(QuickLinksStore.maximumCount) links")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button {
                    quickLinkEditor = QuickLinkEditorRequest(link: nil)
                } label: {
                    Label("Add Quick Link", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(quickLinks.links.count >= QuickLinksStore.maximumCount || quickLinks.storageError != nil)
            }
            LeetBarCard {
                if quickLinks.links.isEmpty && quickLinks.storageError == nil {
                    Text("Your next favorite shortcut goes here.").font(.headline)
                    Text("Add up to four practice links to keep them close in your menu bar.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(quickLinks.links) { link in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(link.url.host ?? link.url.absoluteString)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        linkButton("Move \(link.title) up", symbol: "arrow.up") {
                            changeQuickLinks { try quickLinks.move(id: link.id, by: -1) }
                        }
                        .disabled(link.id == quickLinks.links.first?.id)
                        linkButton("Move \(link.title) down", symbol: "arrow.down") {
                            changeQuickLinks { try quickLinks.move(id: link.id, by: 1) }
                        }
                        .disabled(link.id == quickLinks.links.last?.id)
                        linkButton("Edit \(link.title)", symbol: "pencil") {
                            quickLinkEditor = QuickLinkEditorRequest(link: link)
                        }
                        Button(role: .destructive) {
                            changeQuickLinks { try quickLinks.remove(id: link.id) }
                        } label: {
                            Image(systemName: "trash").frame(width: 24, height: 24)
                        }
                        .help("Remove \(link.title)")
                        .accessibilityLabel("Remove \(link.title)")
                    }
                    .buttonStyle(.borderless)
                    if link.id != quickLinks.links.last?.id { Divider() }
                }
                if let error = quickLinks.storageError ?? quickLinksMessage { errorText(error) }
                if quickLinks.storageError != nil {
                    Button("Reset Quick Links", role: .destructive) { isResettingQuickLinks = true }
                }
            }
        }
    }

    private var accountPage: some View {
        Group {
            LeetBarCard {
                Label(
                    accountStatus,
                    systemImage: account.connectionPhase == .failed ? "exclamationmark.circle" : "person.crop.circle"
                )
                .font(.headline)
                if let username = account.username {
                    Text("@\(username)").foregroundStyle(.secondary)
                }
                Text("Credentials stay in your macOS login Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                if account.hasSavedSession || account.isWorking {
                    HStack {
                        if !showsConnectionForm {
                            Button("Reconnect") {
                                clearCredentialDrafts()
                                isReconnecting = true
                            }
                            .disabled(account.isWorking)
                        }
                        Spacer()
                        Button("Disconnect", role: .destructive) {
                            clearCredentialDrafts()
                            isReconnecting = false
                            account.disconnect()
                        }
                    }
                }
            }
            if showsConnectionForm {
                LeetBarCard {
                    Link(destination: URL(string: "https://leetcode.com/accounts/login/")!) {
                        Label("Open LeetCode Sign-In", systemImage: "arrow.up.right")
                    }
                    .foregroundStyle(theme.accent)
                    LeetCodeCredentialFields(sessionCookie: $sessionCookie, csrfToken: $csrfToken)
                        .disabled(account.isWorking)
                    HStack {
                        if isReconnecting && account.hasSavedSession && !account.isWorking {
                            Button("Cancel", role: .cancel) {
                                isReconnecting = false
                                clearCredentialDrafts()
                            }
                        }
                        Spacer()
                        Button(account.hasSavedSession ? "Reconnect" : "Connect", action: connect)
                            .buttonStyle(.borderedProminent)
                            .disabled(account.isWorking || sessionCookie.isEmpty || csrfToken.isEmpty)
                    }
                }
            }
            if account.isWorking {
                LeetBarConnectionProgress(
                    message: account.connectionPhase.statusMessage ?? "Updating your dashboard...")
            }
            if let message = validationMessage ?? account.message { errorText(message) }
        }
    }

    private var diagnosticsPage: some View {
        Group {
            LeetBarCard {
                LeetBarToggleRow(
                    title: "Enable verbose logging",
                    isOn: Binding(
                        get: { diagnostics.verboseEnabled },
                        set: { diagnostics.setVerboseEnabled($0) }))
                Text(
                    "Warnings and errors are always recorded. Verbose logging adds authentication, network, and cache events."
                )
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Log storage", value: diagnostics.storageBytes.formatted(.byteCount(style: .file)))
                    .font(.callout)
            }
            LeetBarCard {
                HStack {
                    Button("Export Logs…") { diagnostics.export() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Show in Finder") { diagnostics.showInFinder() }
                }
                Button("Clear Logs…", role: .destructive) { isClearingLogs = true }
                Text("Local logs only. Nothing is uploaded automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(diagnostics.isWorking)
            if diagnostics.isWorking { ProgressView().controlSize(.small) }
            if let error = diagnostics.errorMessage {
                errorText(error)
            } else if let status = diagnostics.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Privacy and retention") {
                Text(
                    "Startup metadata is retained with verbose logging off. Logs exclude credentials and account data, but include usage timestamps. Each file is limited to 5 MB and records older than 7 days are removed. Review exports before sharing."
                )
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            }
            .font(.callout)
        }
    }

    private func linkButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 24, height: 24)
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private func errorText(_ message: String) -> some View {
        Text(message).font(.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func clearCredentialDrafts() {
        sessionCookie = ""
        csrfToken = ""
        validationMessage = nil
    }

    private func connect() {
        if let message = LeetCodeSession.validationMessage(sessionCookie: sessionCookie, csrfToken: csrfToken) {
            validationMessage = message
            logger.log(.warning, .invalidCredentials, reason: .invalidCookie)
            return
        }
        do {
            let candidate = try LeetCodeSession(sessionCookie: sessionCookie, csrfToken: csrfToken)
            clearCredentialDrafts()
            account.connect(candidate)
        } catch {
            logger.logFailure(.invalidCredentials, error: error)
            clearCredentialDrafts()
            validationMessage = LeetCodeClient.message(for: error)
        }
    }

    private func changeQuickLinks(_ action: () throws -> Void) {
        do {
            try action()
            quickLinksMessage = nil
        } catch {
            quickLinksMessage = error.localizedDescription
        }
    }
}

private struct QuickLinkEditorRequest: Identifiable {
    let id = UUID()
    let link: QuickLink?
}

private struct QuickLinkEditor: View {
    @ObservedObject var store: QuickLinksStore
    let original: QuickLink?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var address: String
    @State private var message: String?

    init(store: QuickLinksStore, original: QuickLink?) {
        self.store = store
        self.original = original
        _title = State(initialValue: original?.title ?? "")
        _address = State(initialValue: original?.url.absoluteString ?? "")
    }

    var body: some View {
        VStack(spacing: 24) {
            LeetBarPageHeader(
                title: original == nil ? "Add Quick Link" : "Edit Quick Link",
                subtitle: "A shortcut to your next practice session.")
            LeetBarCard {
                Form {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("quickLinkTitle")
                    TextField("Link", text: $address, prompt: Text("https://"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("quickLinkURL")
                }
                .formStyle(.columns)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try store.save(id: original?.id, title: title, address: address)
                        dismiss()
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || address.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background { LeetBarSurface() }
    }
}
