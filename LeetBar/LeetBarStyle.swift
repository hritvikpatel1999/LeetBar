import SwiftUI

enum LeetBarStyle {
    static let contentWidth: CGFloat = 400
}

enum AppTheme: String, CaseIterable, Sendable {
    static let storageKey = "appTheme"
    case teal, ocean, violet, sunset

    var title: String { rawValue.capitalized }

    var accent: Color {
        switch self {
        case .teal: .teal
        case .ocean: .blue
        case .violet: .purple
        case .sunset: .orange
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.teal
}

extension EnvironmentValues {
    var leetBarTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    func leetBarAppearance() -> some View {
        modifier(LeetBarAppearance())
    }
}

private struct LeetBarAppearance: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .teal

    func body(content: Content) -> some View {
        content
            .background { LeetBarSurface() }
            .environment(\.leetBarTheme, theme)
            .tint(theme.accent)
            .accentColor(theme.accent)
    }
}

struct LeetBarSurface: View {
    var isCard = false
    @Environment(\.leetBarTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(nsColor: isCard ? .controlBackgroundColor : .windowBackgroundColor)
            .overlay(theme.accent.opacity(colorScheme == .dark ? 0.07 : 0.035))
    }
}

struct LeetBarThemePicker: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .teal

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTheme.allCases, id: \.self) { option in
                Button {
                    theme = option
                } label: {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(option.accent)
                            .frame(width: 28, height: 28)
                            .overlay(alignment: .bottomTrailing) {
                                if theme == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.primary, Color(nsColor: .windowBackgroundColor))
                                        .font(.caption)
                                }
                            }
                        Text(option.title).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title) theme")
                .accessibilityValue(theme == option ? "Selected" : "Not selected")
                .accessibilityIdentifier("theme-\(option.rawValue)")
            }
        }
        .background { ThemePickerInitialFocus().frame(width: 0, height: 0) }
    }
}

private struct ThemePickerInitialFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusView { FocusView() }

    func updateNSView(_ nsView: FocusView, context: Context) {}

    final class FocusView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.initialFirstResponder = self
            // Start outside the buttons, without disabling their subsequent keyboard focus.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}

struct LeetBarPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

struct LeetBarCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.clear)
                .background {
                    LeetBarSurface(isCard: true)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.06))
                }
        }
    }
}

struct LeetBarToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct LeetCodeCredentialFields: View {
    @Binding var sessionCookie: String
    @Binding var csrfToken: String
    var identifierPrefix = "account"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("LEETCODE_SESSION", text: $sessionCookie)
            field("csrftoken", text: $csrfToken)
            Text(
                "Used only to authenticate your requests to LeetCode. Saved in macOS Keychain, never in logs. Never share these values with anyone."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption)
            SecureField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .help("Paste only the \(label) value from the same signed-in LeetCode browser session.")
                .accessibilityIdentifier("\(identifierPrefix)-\(label)")
        }
    }
}

struct LeetBarConnectionProgress: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(message).font(.callout)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connection-progress")
    }
}
