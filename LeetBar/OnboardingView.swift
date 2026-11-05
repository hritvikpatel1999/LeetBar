import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var onboarding: OnboardingStore
    @ObservedObject var account: AccountStore
    @Binding var showStreak: Bool
    @Binding var showQuickLinks: Bool
    @Binding var showUpcomingContests: Bool
    @Binding var showTodaySection: Bool
    @Binding var showStudyPlans: Bool
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch onboarding.step {
        case .welcome: "Welcome to LeetBar"
        case .signIn: "Sign in to LeetCode"
        case .credentials: "Connect your account"
        case .preferences: "Make LeetBar yours"
        case .ready, .complete: "You're all set!"
        }
    }

    private var subtitle: String {
        switch onboarding.step {
        case .welcome: "Your daily LeetCode check-in, right in the menu bar."
        case .signIn: "Sign in with your usual method, then return here."
        case .credentials: "Paste both cookie values from the same signed-in browser session."
        case .preferences: "You're connected. Choose what you'd like to see."
        case .ready, .complete: "Small icon. Big coding energy."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Step \(onboarding.step.number) of \(OnboardingStep.ready.number)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
            ScrollView {
                VStack(spacing: 18) {
                    if onboarding.step == .welcome || onboarding.step == .ready {
                        Image("LeetCodeLogo")
                            .resizable().scaledToFit().frame(width: 56, height: 56)
                            .accessibilityHidden(true)
                    }
                    LeetBarPageHeader(title: title, subtitle: subtitle)
                    pageContent
                    if let message = onboarding.errorMessage {
                        Text(message)
                            .font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboarding-error")
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: LeetBarStyle.contentWidth)
                .frame(maxWidth: .infinity, minHeight: 340)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            VStack(spacing: 12) {
                HStack {
                    if onboarding.step == .signIn || onboarding.step == .credentials {
                        Button("Back") { onboarding.goBack() }
                            .disabled(onboarding.isConnecting || account.isWorking)
                    }
                    Spacer()
                    primaryButton
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Text("You can close this window and continue later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(width: 500, height: 500)
        .background { LeetBarSurface() }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch onboarding.step {
        case .welcome:
            Text("Look for the LeetBar icon at the top of your screen.")
                .font(.callout).foregroundStyle(.secondary)
        case .signIn:
            Button("Open LeetCode") {
                if !NSWorkspace.shared.open(URL(string: "https://leetcode.com/accounts/login/")!) {
                    onboarding.browserOpenFailed()
                }
            }
            .controlSize(.large)
            Text("Signing in to your browser doesn't connect LeetBar yet.")
                .font(.caption).foregroundStyle(.secondary)
        case .credentials:
            LeetBarCard {
                LeetCodeCredentialFields(
                    sessionCookie: $onboarding.sessionCookie, csrfToken: $onboarding.csrfToken,
                    identifierPrefix: "onboarding")
            }
            .disabled(onboarding.isConnecting || account.isWorking)
            if onboarding.isConnecting {
                LeetBarConnectionProgress(message: account.connectionPhase.statusMessage ?? "Connecting...")
            }
            Text("Draft values stay in memory while LeetBar is running; after quitting, paste them again.")
                .font(.caption2).foregroundStyle(.secondary)
        case .preferences:
            LeetBarCard {
                PreferencesControls(
                    showStreak: $showStreak, showQuickLinks: $showQuickLinks,
                    showUpcomingContests: $showUpcomingContests, showTodaySection: $showTodaySection,
                    showStudyPlans: $showStudyPlans)
            }
            .toggleStyle(.switch)
            .multilineTextAlignment(.leading)
            if account.message != nil || account.snapshot?.issues.isEmpty == false {
                Text("Account connected. Some dashboard data is unavailable; you can retry from the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .ready, .complete:
            HStack(spacing: 8) {
                Image("LeetCodeMenuBar")
                    .renderingMode(.template)
                    .accessibilityHidden(true)
                Text("Find LeetBar in your menu bar.")
            }
            Text("Your next solve is just a click away.")
                .foregroundStyle(.secondary)
            Text("Happy LeetCoding. May your streak be mighty!")
                .font(.callout)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch onboarding.step {
        case .welcome:
            Button("Connect LeetCode") { onboarding.advance() }
        case .signIn:
            Button("I'm signed in") { onboarding.advance() }
        case .credentials:
            Button("Connect") { Task { await onboarding.connect() } }
                .disabled(onboarding.isConnecting || account.isWorking)
        case .preferences:
            Button("Continue") { onboarding.advance() }
        case .ready, .complete:
            Button("Let's LeetCode!") {
                onboarding.finish()
                if onboarding.isComplete { dismiss() }
            }
        }
    }
}
