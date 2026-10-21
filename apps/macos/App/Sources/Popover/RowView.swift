import DocketActivity
import DocketCore
import SwiftUI

/// One pull request, three lines (`docs/05-design.md` §6.1). The whole row opens it (FR-42).
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
    @State private var isHovered = false

    private var pullRequest: PullRequest { item.pullRequest }
    private var age: TimeInterval { now.timeIntervalSince(pullRequest.createdAt) }
    private var waited: TimeInterval { now.timeIntervalSince(item.waitingSince) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if item.isMarked {
                    Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(Color.accentMarked)
                } else {
                    Color.clear
                }
            }
            .frame(width: 12, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                firstLine
                Text(verbatim: pullRequest.title)
                    .font(.body)
                    .foregroundStyle(placement == .ignored ? Color.textSecondary : Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(pullRequest.title)
                thirdLine
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(
                isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { actions.open(pullRequest.url) }
        .contextMenu { RowMenu(item: item, actions: actions) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RowAccessibility.label(for: item, placement: placement, now: now))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.open(pullRequest.url) }
    }

    private var firstLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(pullRequest.repository) #\(pullRequest.number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if placement == .reviewRequested {
                AgeLabel(
                    elapsed: waited,
                    prefix: String(localized: "waited", comment: "Before the waited time of a review request"))
            } else {
                AgeLabel(elapsed: age)
            }
            if item.mute == .all {
                Image(systemName: "bell.slash")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel(Text("Muted", comment: "VoiceOver label of the muted marker"))
            }
        }
    }

    private var thirdLine: some View {
        HStack(spacing: 6) {
            if placement == .reviewRequested {
                if let author = pullRequest.author?.login {
                    Text("by @\(author)", comment: "The author of a pull request in Review requested")
                        .font(.subheadline).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                if let team = teamText {
                    Text(verbatim: team).font(.subheadline).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                StatusChip(status: item.status, secondary: true)
                Text(verbatim: "· \(Age.short(age))").font(.subheadline.monospacedDigit()).foregroundStyle(
                    Color.textSecondary)
            } else if placement == .ignored {
                Text(verbatim: item.status.label).font(.subheadline).foregroundStyle(Color.textSecondary)
            } else {
                StatusChip(status: item.status)
                if pullRequest.isDraft { DraftChip() }
                if placement == .involved, let author = pullRequest.author?.login {
                    Text("by @\(author)", comment: "The author of a pull request in Involved")
                        .font(.subheadline).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                ForEach(Array(item.reviewers.prefix(3).enumerated()), id: \.offset) { _, entry in
                    ReviewerLabel(entry: entry)
                }
                if item.reviewers.count > 3 {
                    Text(verbatim: "+\(item.reviewers.count - 3)").font(.subheadline).foregroundStyle(
                        Color.textSecondary)
                }
            }
            ForEach(item.tags, id: \.self) { tag in
                TagChip(tag: tag) { actions.filterTag(tag) }
            }
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
        Button(String(localized: "Open in Browser", comment: "Row context menu")) { actions.open(pullRequest.url) }
        Button(String(localized: "Copy URL", comment: "Row context menu")) {
            actions.copy(pullRequest.url.absoluteString)
        }
        Button(String(localized: "Copy Reference", comment: "Row context menu")) { actions.copy(pullRequest.ref) }
        Divider()
        Button(String(localized: "Edit Tags…", comment: "Row context menu")) { actions.editTags(item) }
        Button(String(localized: "Filter to \(pullRequest.repository)", comment: "Row context menu")) {
            actions.filterRepository(pullRequest.repository)
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
