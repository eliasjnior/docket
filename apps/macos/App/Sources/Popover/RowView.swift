import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// One pull request (`docs/05-design.md` §6.1): a status rail, the title, then one line of details.
/// The whole row opens it (FR-42); an unseen row is tinted and its title bold (FR-46).
struct RowView: View {
    enum Placement {
        case reviewRequested
        case mine
        case involved
        case ignored
    }

    let item: WatchedPullRequest
    let placement: Placement
    let now: Date
    let actions: RowActions
    var isFocused = false
    @State private var isHovered = false

    private var pullRequest: PullRequest { item.pullRequest }
    private var age: TimeInterval { now.timeIntervalSince(pullRequest.createdAt) }
    private var waited: TimeInterval { now.timeIntervalSince(item.waitingSince) }
    private var sinceActivity: TimeInterval { now.timeIntervalSince(item.lastActivity) }
    private var unseen: Bool { item.isUnseen && placement != .ignored }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(placement == .ignored ? Color.textTertiary : item.status.color)
                .opacity(unseen ? 1 : 0.55)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pullRequest.title)
                    .font(.body.weight(unseen ? .semibold : .regular))
                    .foregroundStyle(unseen ? Color.textPrimary : Color.textSeen)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(pullRequest.title)
                details
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(unseen ? Color.accent.opacity(0.10) : .clear)
        .overlay {
            if isHovered || isFocused {
                Rectangle().fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.12))
            }
        }
        .overlay {
            if isFocused { Rectangle().strokeBorder(Color.accent, lineWidth: 2) }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { actions.open(item) }
        .contextMenu { RowMenu(item: item, actions: actions) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RowAccessibility.label(for: item, placement: placement, now: now))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.open(item) }
    }

    /// One line that never wraps: reviewers collapse to `+N` first, then labels (`docs/05-design.md` §6.1).
    private var details: some View {
        HStack(spacing: 6) {
            detailLine
            Spacer(minLength: 4)
            trailing
        }
    }

    private var trailing: some View {
        HStack(spacing: 4) {
            if item.mute == .all {
                Image(systemName: "bell.slash")
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel(Text("Muted", comment: "VoiceOver label of the muted marker"))
            }
            let shown = placement == .reviewRequested ? waited : age
            ActivityLabel(elapsed: sinceActivity, besideAge: shown)
            AgeLabel(elapsed: shown)
        }
        .font(.subheadline)
        .fixedSize()
        .help(
            String(
                localized: "Last activity \(Age.short(sinceActivity)) ago · opened \(Age.short(age)) ago",
                comment: "Tooltip of a row's times"))
    }

    /// The size outlasts the labels, the team and the author: it is what decides whether to review now.
    /// Labels leave first, then reviewers and the team, then the author, and the size last.
    private var detailLine: some View {
        DropLayout(spacing: 6) {
            // Outside *Review requested* no header names the repository, so the row does.
            if placement != .reviewRequested {
                RepositoryTag(repository: pullRequest.repository).layoutValue(key: DropShrinks.self, value: true)
            }
            Text(verbatim: "#\(pullRequest.number)").font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
            if let position = item.stackPosition { StackBadge(position: position) }
            if placement == .ignored {
                Text(verbatim: item.status.label).font(.subheadline).foregroundStyle(Color.textSecondary)
            } else {
                StatusChip(status: item.status, short: placement == .reviewRequested)
                    .help(item.waitingDetails ?? "")
            }
            if pullRequest.isDraft, placement != .ignored { DraftChip() }
            if placement != .ignored { SizeLabel(pullRequest: pullRequest).layoutValue(key: DropRank.self, value: 1) }
            if placement != .mine, let author = pullRequest.author?.login {
                Text(verbatim: "@\(author)").font(.subheadline).foregroundStyle(Color.textSecondary)
                    .layoutValue(key: DropRank.self, value: 2)
            }
            if placement == .reviewRequested, let team = teamText {
                Text(verbatim: team).font(.subheadline).foregroundStyle(Color.textSecondary)
                    .layoutValue(key: DropRank.self, value: 3)
            }
            if placement == .mine {
                ForEach(Array(item.reviewers.enumerated()), id: \.offset) { _, entry in
                    ReviewerLabel(entry: entry).layoutValue(key: DropRank.self, value: 3)
                }
            }
            ForEach(pullRequest.labels, id: \.name) { LabelChip(label: $0).layoutValue(key: DropRank.self, value: 4) }
        }
        .lineLimit(1)
    }

    private var teamText: String? {
        guard let request = item.request, request.team != nil || request.throughUnknownTeam else { return nil }
        if request.throughUnknownTeam {
            return String(localized: "via a team", comment: "A review request through a team Docket cannot name")
        }
        return request.team.map { String(localized: "via \($0.handle)", comment: "A review request through a team") }
    }
}

/// Right click on a row (`docs/05-design.md` §6.5).
struct RowMenu: View {
    let item: WatchedPullRequest
    let actions: RowActions

    var body: some View {
        let pullRequest = item.pullRequest
        Button(String(localized: "Open in Browser", comment: "Row context menu")) { actions.open(item) }
        Button(String(localized: "Copy URL", comment: "Row context menu")) {
            actions.copy(pullRequest.url.absoluteString)
        }
        Button(String(localized: "Copy Reference", comment: "Row context menu")) { actions.copy(pullRequest.ref) }
        PullRequestLinksMenu(item: item, open: actions.open)
        ForEach(item.waitingChecks.filter { $0.url != nil }, id: \.name) { check in
            Button(String(localized: "Open \(check.name)", comment: "Row context menu: a waiting check")) {
                check.url.map(actions.open)
            }
        }
        Divider()
        let jira = actions.jiraLink(item)
        Button(String(localized: "Open in Jira", comment: "Row context menu")) { jira.map(actions.open) }
            .disabled(jira == nil)
        Button(String(localized: "Review with AI", comment: "Row context menu")) { actions.reviewWithAI(item) }
        Button(String(localized: "Summarize with AI", comment: "Row context menu")) { actions.summarizeWithAI(item) }
        Divider()
        Button(String(localized: "Filter to \(pullRequest.repository)", comment: "Row context menu")) {
            actions.filterRepository(pullRequest.repository)
        }
        if item.isUnseen {
            Button(String(localized: "Mark as Seen", comment: "Row context menu")) { actions.markSeen([item.id]) }
        }
        Divider()
        if !item.isIgnored {
            if item.role == .reviewRequested {
                Toggle(
                    String(localized: "Mute Reminders", comment: "Row context menu"),
                    isOn: Binding(
                        get: { item.mute == .reminders }, set: { actions.setMute(item, $0 ? .reminders : nil) }))
            }
            Toggle(
                String(localized: "Mute Notifications", comment: "Row context menu"),
                isOn: Binding(get: { item.mute == .all }, set: { actions.setMute(item, $0 ? .all : nil) }))
            Button(String(localized: "Ignore", comment: "Row context menu")) { actions.setIgnored(item, true) }
        } else {
            Button(String(localized: "Stop Ignoring", comment: "Row context menu")) { actions.setIgnored(item, false) }
        }
    }
}
