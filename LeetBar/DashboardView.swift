import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var account: AccountStore
    @ObservedObject var quickLinks: QuickLinksStore
    let showQuickLinks: Bool
    let showUpcomingContests: Bool
    let showTodaySection: Bool
    @State private var isDailyRowHovered = false
    @State private var isTodayExpanded = false
    @State private var isTodayHeaderHovered = false
    @State private var areContestsExpanded = false
    @State private var isContestHeaderHovered = false
    @State private var areQuickLinksExpanded = false
    @State private var isQuickLinksHeaderHovered = false
    @State private var hoveredQuickLinkID: UUID?
    @State private var contentHeight: CGFloat = 200

    private struct ContentHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private var maximumHeight: CGFloat {
        min(620, max(200, (NSScreen.main?.visibleFrame.height ?? 720) - 48))
    }

    private var hoverShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
    }

    private var completion: Bool? {
        account.snapshot?.daily?.isCompleted
    }

    private var dailyTitle: String {
        account.snapshot?.daily?.question.title ?? "Unavailable"
    }

    private var dailyDifficulty: String {
        account.snapshot?.daily?.question.difficulty ?? "--"
    }

    private var completionText: String {
        completion.map { $0 ? "Completed" : "Not completed" } ?? "Unknown"
    }

    private var contestRatingText: String {
        "Contest rating \(account.snapshot?.contestRating?.formatted() ?? "--")"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                content(asOf: context.date)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
                        }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 360, height: min(contentHeight, maximumHeight))
        .onPreferenceChange(ContentHeightKey.self) { height in
            if height > 0 { contentHeight = ceil(height) }
        }
        .tint(.teal)
        .task {
            account.refreshIfNeeded()
        }
    }

    private func content(asOf now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image("LeetCodeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if let username = account.username {
                            Link(
                                "@\(username)",
                                destination: URL(string: "https://leetcode.com/u/")!
                                    .appendingPathComponent(username, isDirectory: true)
                            )
                            .buttonStyle(.plain)
                            .help("Open LeetCode profile")
                            .accessibilityLabel("Open LeetCode profile for \(username)")
                        } else {
                            Text(account.isWorking ? "Connecting..." : "Not connected")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    Text(contestRatingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(contestRatingText)
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
            }

            Divider()

            if account.hasSavedSession {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        sectionHeading("Daily Problem", symbol: "calendar")
                        Spacer(minLength: 8)
                        Text(account.snapshot?.daily?.date ?? "--")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize()
                    }

                    if let url = account.snapshot?.daily?.url {
                        Link(destination: url) {
                            dailyProblemRow
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                        .background {
                            hoverShape
                                .fill(isDailyRowHovered ? Color.primary.opacity(0.07) : Color.clear)
                        }
                        .clipShape(hoverShape)
                        .contentShape(hoverShape)
                        .onHover { isDailyRowHovered = $0 }
                        .onDisappear { isDailyRowHovered = false }
                        .help("\(dailyTitle) - \(completionText)")
                        .accessibilityLabel("\(dailyTitle), \(dailyDifficulty), \(completionText)")
                        .padding(.horizontal, -4)
                    } else {
                        dailyProblemRow
                    }

                    Text("LeetCode streak: \(account.snapshot?.streak.map(String.init) ?? "--")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if account.snapshot?.streak == nil {
                        Text("Streak unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                if showTodaySection {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            isTodayExpanded.toggle()
                        } label: {
                            HStack(spacing: 8) {
                                sectionHeading("Today", symbol: "chart.bar")
                                    .fixedSize()
                                Spacer(minLength: 8)
                                Text(todayCaption(asOf: now))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: isTodayExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12, height: 12)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 4)
                            .frame(minHeight: 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background {
                            hoverShape
                                .fill(isTodayHeaderHovered ? Color.primary.opacity(0.07) : Color.clear)
                        }
                        .clipShape(hoverShape)
                        .contentShape(hoverShape)
                        .onHover { isTodayHeaderHovered = $0 }
                        .onDisappear { isTodayHeaderHovered = false }
                        .help(isTodayExpanded ? "Collapse today" : "Expand today")
                        .accessibilityLabel("Today")
                        .accessibilityValue("\(todayCaption(asOf: now)), \(isTodayExpanded ? "Expanded" : "Collapsed")")
                        .padding(.horizontal, -4)

                        if isTodayExpanded {
                            VStack(spacing: 4) {
                                metric("Submissions", value: stats(asOf: now)?.submissions)
                                metric("Problems Solved", value: stats(asOf: now)?.problemsSolved)
                            }
                        }
                    }

                    Divider()
                }

                if showUpcomingContests {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            areContestsExpanded.toggle()
                        } label: {
                            HStack(spacing: 8) {
                                sectionHeading("Upcoming Contests", symbol: "trophy")
                                    .fixedSize()
                                Spacer(minLength: 8)
                                Text(contestSummary(asOf: now))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Image(systemName: areContestsExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12, height: 12)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 4)
                            .frame(minHeight: 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background {
                            hoverShape
                                .fill(isContestHeaderHovered ? Color.primary.opacity(0.07) : Color.clear)
                        }
                        .clipShape(hoverShape)
                        .contentShape(hoverShape)
                        .onHover { isContestHeaderHovered = $0 }
                        .onDisappear { isContestHeaderHovered = false }
                        .help(areContestsExpanded ? "Collapse contests" : "Expand contests")
                        .accessibilityLabel("Upcoming Contests")
                        .accessibilityValue(
                            "\(contestSummary(asOf: now)), \(areContestsExpanded ? "Expanded" : "Collapsed")"
                        )
                        .padding(.horizontal, -4)

                        if areContestsExpanded {
                            if let contests = account.snapshot?.contests {
                                let upcoming = contests.filter { $0.end > now }
                                if upcoming.isEmpty {
                                    Text("No upcoming contests")
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(upcoming) { contest in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Link(contest.title, destination: contest.url)
                                            .font(.headline)
                                        Text(
                                            contest.start,
                                            format: .dateTime.weekday().month(.abbreviated).day().hour().minute()
                                        )
                                        .font(.subheadline)
                                        if contest.start > now {
                                            HStack(spacing: 4) {
                                                Text("Starts in")
                                                Text(contest.start, style: .relative)
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        } else {
                                            Text("In progress").font(.caption).foregroundStyle(.green)
                                        }
                                    }
                                }
                            } else {
                                Text("Contests unavailable").foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()
                }
            } else {
                SettingsLink {
                    Label("Connect LeetCode", systemImage: "key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Divider()
            }

            if showQuickLinks {
                quickLinksSection
                Divider()
            }

            if let message = account.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            ForEach(account.snapshot?.issues ?? [], id: \.self) { issue in
                Text(issue).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Group {
                    if let checked = account.snapshot?.checkedAt {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last checked")
                            Text(checked, format: .dateTime.month(.abbreviated).day().hour().minute())
                        }
                    } else {
                        Text(account.isWorking ? "Connecting..." : "Not synced")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                if account.hasSavedSession {
                    Button {
                        account.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(account.isWorking)
                    .help("Refresh LeetCode")
                    .accessibilityLabel("Refresh LeetCode")
                }
                if account.isWorking {
                    ProgressView().controlSize(.small)
                }
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .help("Quit LeetBar")
                .accessibilityLabel("Quit LeetBar")
            }
        }
        .padding(18)
    }

    private var quickLinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                areQuickLinksExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    sectionHeading("Quick Links", symbol: "link")
                        .fixedSize()
                    Spacer(minLength: 8)
                    Text(quickLinks.storageError == nil ? "\(quickLinks.links.count)" : "--")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: areQuickLinksExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 24)
                .contentShape(hoverShape)
            }
            .buttonStyle(.plain)
            .background {
                hoverShape.fill(isQuickLinksHeaderHovered ? Color.primary.opacity(0.07) : Color.clear)
            }
            .clipShape(hoverShape)
            .contentShape(hoverShape)
            .animation(.easeInOut(duration: 0.12), value: isQuickLinksHeaderHovered)
            .onHover { isQuickLinksHeaderHovered = $0 }
            .onDisappear { isQuickLinksHeaderHovered = false }
            .help(areQuickLinksExpanded ? "Collapse quick links" : "Expand quick links")
            .accessibilityLabel("Quick Links")
            .accessibilityValue("\(quickLinks.links.count) links, \(areQuickLinksExpanded ? "Expanded" : "Collapsed")")
            .padding(.horizontal, -4)

            if areQuickLinksExpanded {
                if quickLinks.storageError != nil {
                    Text("Quick links unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SettingsLink {
                        Text("Manage Quick Links")
                    }
                } else if quickLinks.links.isEmpty {
                    SettingsLink {
                        Label("Add Quick Link", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(quickLinks.links) { link in
                        Link(destination: link.url) {
                            HStack(spacing: 8) {
                                Text(link.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12, height: 12)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 4)
                            .frame(minHeight: 26)
                            .contentShape(hoverShape)
                        }
                        .buttonStyle(.plain)
                        .background {
                            hoverShape.fill(hoveredQuickLinkID == link.id ? Color.primary.opacity(0.07) : Color.clear)
                        }
                        .clipShape(hoverShape)
                        .contentShape(hoverShape)
                        .animation(.easeInOut(duration: 0.12), value: hoveredQuickLinkID == link.id)
                        .onHover { hoveredQuickLinkID = $0 ? link.id : nil }
                        .onDisappear {
                            if hoveredQuickLinkID == link.id { hoveredQuickLinkID = nil }
                        }
                        .help("\(link.title)\n\(link.url.absoluteString)")
                        .accessibilityLabel("Open \(link.title)")
                        .padding(.horizontal, -4)
                    }
                }
            }
        }
    }

    private var dailyProblemRow: some View {
        HStack(spacing: 8) {
            Text(dailyTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(dailyDifficulty)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Image(
                systemName: completion.map { $0 ? "checkmark.circle.fill" : "circle.dashed" } ?? "questionmark.circle"
            )
            .foregroundStyle(completion == true ? Color.green : Color.secondary)
            .frame(width: 20, height: 20, alignment: .trailing)
            .accessibilityLabel(completionText)
            .help(completionText)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func contestSummary(asOf now: Date) -> String {
        guard let contests = account.snapshot?.contests else {
            return account.isWorking ? "Loading..." : "Unavailable"
        }
        guard let next = contests.filter({ $0.end > now }).min(by: { $0.start < $1.start }) else {
            return "None scheduled"
        }
        return ContestDayLabel.text(for: next.start, relativeTo: now)
    }

    private func todayCaption(asOf now: Date) -> String {
        let date = now.formatted(.dateTime.month(.abbreviated).day())
        let timeZone = TimeZone.current.identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " / ")
        return "\(date), \(timeZone)"
    }

    private func stats(asOf now: Date) -> DailyStats? {
        guard let snapshot = account.snapshot,
            Calendar.current.isDate(snapshot.checkedAt, inSameDayAs: now)
        else { return nil }
        return snapshot.stats
    }

    private func sectionHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func metric(_ title: String, value: Int?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.map(String.init) ?? "--")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
    }
}
