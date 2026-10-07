import SwiftUI

struct SettingsView: View {
    @Binding var showStreak: Bool
    @Binding var showQuickLinks: Bool
    @Binding var showUpcomingContests: Bool
    @Binding var showTodaySection: Bool
    @ObservedObject var account: AccountStore
    @ObservedObject var quickLinks: QuickLinksStore
    @State private var sessionCookie = ""
    @State private var csrfToken = ""
    @State private var validationMessage: String?
    @State private var quickLinkEditor: QuickLinkEditorRequest?
    @State private var quickLinksMessage: String?
    @State private var isResettingQuickLinks = false

    var body: some View {
        Form {
            Section("Sections") {
                Toggle("Show Quick Links", isOn: $showQuickLinks)
                Toggle("Show Upcoming Contests", isOn: $showUpcomingContests)
                Toggle("Show Today section", isOn: $showTodaySection)
            }
            Section("Quick Links") {
                HStack {
                    Text("\(quickLinks.links.count) of \(QuickLinksStore.maximumCount)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        quickLinkEditor = QuickLinkEditorRequest(link: nil)
                    } label: {
                        Label("Add Quick Link", systemImage: "plus")
                    }
                    .help("Add Quick Link")
                    .disabled(quickLinks.links.count >= QuickLinksStore.maximumCount || quickLinks.storageError != nil)
                }
                ForEach(quickLinks.links) { link in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(link.url.host ?? link.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            changeQuickLinks { try quickLinks.move(id: link.id, by: -1) }
                        } label: {
                            Image(systemName: "arrow.up").frame(width: 24, height: 24)
                        }
                        .disabled(link.id == quickLinks.links.first?.id)
                        .help("Move \(link.title) up")
                        .accessibilityLabel("Move \(link.title) up")
                        Button {
                            changeQuickLinks { try quickLinks.move(id: link.id, by: 1) }
                        } label: {
                            Image(systemName: "arrow.down").frame(width: 24, height: 24)
                        }
                        .disabled(link.id == quickLinks.links.last?.id)
                        .help("Move \(link.title) down")
                        .accessibilityLabel("Move \(link.title) down")
                        Button {
                            quickLinkEditor = QuickLinkEditorRequest(link: link)
                        } label: {
                            Image(systemName: "pencil").frame(width: 24, height: 24)
                        }
                        .help("Edit \(link.title)")
                        .accessibilityLabel("Edit \(link.title)")
                        Button(role: .destructive) {
                            changeQuickLinks { try quickLinks.remove(id: link.id) }
                        } label: {
                            Image(systemName: "trash").frame(width: 24, height: 24)
                        }
                        .help("Remove \(link.title)")
                        .accessibilityLabel("Remove \(link.title)")
                    }
                    .buttonStyle(.borderless)
                }
                if let error = quickLinks.storageError ?? quickLinksMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if quickLinks.storageError != nil {
                    Button("Reset Quick Links", role: .destructive) { isResettingQuickLinks = true }
                }
            }
            Section("LeetCode Account") {
                LabeledContent(
                    "Account", value: account.username ?? (account.hasSavedSession ? "Session saved" : "Not connected"))
                Link(destination: URL(string: "https://leetcode.com/accounts/login/")!) {
                    Label("Open LeetCode Sign-In", systemImage: "arrow.up.right")
                }
                SecureField("LEETCODE_SESSION", text: $sessionCookie)
                    .privacySensitive()
                    .help("The LEETCODE_SESSION cookie value from your signed-in LeetCode browser tab.")
                SecureField("csrftoken", text: $csrfToken)
                    .privacySensitive()
                    .help("The csrftoken cookie value from the same LeetCode browser tab.")
                HStack {
                    Button {
                        do {
                            let candidate = try LeetCodeSession(sessionCookie: sessionCookie, csrfToken: csrfToken)
                            sessionCookie = ""
                            csrfToken = ""
                            validationMessage = nil
                            account.connect(candidate)
                        } catch {
                            sessionCookie = ""
                            csrfToken = ""
                            validationMessage = LeetCodeClient.message(for: error)
                        }
                    } label: {
                        Label(account.hasSavedSession ? "Reconnect" : "Connect", systemImage: "key")
                    }
                    .disabled(account.isWorking || sessionCookie.isEmpty || csrfToken.isEmpty)
                    if account.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if account.hasSavedSession || account.isWorking {
                        Button("Disconnect", role: .destructive) {
                            sessionCookie = ""
                            csrfToken = ""
                            account.disconnect()
                        }
                    }
                }
                LabeledContent("Credential storage", value: "macOS login Keychain")
                if let message = validationMessage ?? account.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Menu Bar") {
                Toggle("Show streak count", isOn: $showStreak)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 500)
        .sheet(item: $quickLinkEditor) { request in
            QuickLinkEditor(store: quickLinks, original: request.link)
        }
        .alert("Reset Quick Links?", isPresented: $isResettingQuickLinks) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { quickLinks.reset() }
        } message: {
            Text("The saved quick-link data will be removed. Your LeetCode connection will not change.")
        }
        .task { account.restore() }
        .onDisappear {
            sessionCookie = ""
            csrfToken = ""
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
        VStack(alignment: .leading, spacing: 16) {
            Text(original == nil ? "Add Quick Link" : "Edit Quick Link")
                .font(.headline)
            Form {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("quickLinkTitle")
                TextField("Link", text: $address, prompt: Text("https://"))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("quickLinkURL")
            }
            .formStyle(.columns)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
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
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || address.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
