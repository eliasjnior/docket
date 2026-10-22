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
                    .foregroundStyle(unseen ? Color.textPrimary : Color.textSecondary)
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
            ViewThatFits(in: .horizontal) {
                detailLine(reviewers: 3, labels: pullRequest.labels.count)
                detailLine(reviewers: 1, labels: pullRequest.labels.count)
                detailLine(reviewers: 0, labels: 2)
                detailLine(reviewers: 0, labels: 0)
                StatusChip(status: item.status, short: true)
            }
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
            if placement == .reviewRequested {
                AgeLabel(elapsed: waited)
            } else {
                AgeLabel(elapsed: age)
            }
        }
        .font(.subheadline)
        .fixedSize()
    }

    private func detailLine(reviewers shownReviewers: Int, labels shownLabels: Int) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: "#\(pullRequest.number)").font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
            if placement == .ignored {
                Text(verbatim: item.status.label).font(.subheadline).foregroundStyle(Color.textSecondary)
            } else {
                StatusChip(status: item.status, short: placement == .reviewRequested)
            }
            if pullRequest.isDraft, placement != .ignored { DraftChip() }
            if placement != .mine, let author = pullRequest.author?.login {
                Text(verbatim: "@\(author)").font(.subheadline).foregroundStyle(Color.textSecondary)
            }
            if placement == .reviewRequested, let team = teamText, shownReviewers > 0 {
                Text(verbatim: team).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
            if placement == .mine {
                ForEach(Array(item.reviewers.prefix(shownReviewers).enumerated()), id: \.offset) { _, entry in
                    ReviewerLabel(entry: entry)
                }
                if item.reviewers.count > shownReviewers {
                    Text(verbatim: "+\(item.reviewers.count - shownReviewers)").font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            ForEach(pullRequest.labels.prefix(shownLabels), id: \.name) { LabelChip(label: $0) }
            if pullRequest.labels.count > shownLabels {
                Text(verbatim: "+\(pullRequest.labels.count - shownLabels)").font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
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
