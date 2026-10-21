import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// The three role sections, always present, and Ignored while something is ignored (`docs/05-design.md` §5.3).
struct SectionsView: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel
    let actions: PopoverActions
    let now: Date

    var body: some View {
        let sections = watch.sections(tag: model.tagFilter, repository: model.repositoryFilter)
        let filtering = model.tagFilter != nil
        VStack(alignment: .leading, spacing: 0) {
            if watch.config.selection.mode == .only, watch.config.selection.includedRepositories.isEmpty,
                watch.config.selection.includedOwners.isEmpty
            {
                EmptyLine(text: String(localized: "No repositories selected.", comment: "Empty state in only mode"))
                Button(
                    String(localized: "Choose Repositories…", comment: "Empty state button"),
                    action: actions.openSettings
                )
                .padding(.horizontal, 24)
            }
            section(
                .reviewRequested, String(localized: "Review requested", comment: "Section header"),
                count: sections.reviewRequestedCount,
                marked: sections.reviewRequested.flatMap(\.items).contains(where: \.isMarked)
            ) {
                if sections.reviewRequested.isEmpty {
                    EmptyLine(
                        text: filtering
                            ? emptyTag : String(localized: "No reviews waiting on you.", comment: "Empty state"))
                }
                ForEach(sections.reviewRequested) { group in
                    HStack {
                        Text(verbatim: group.repository)
                        Spacer()
                        Text(verbatim: "\(group.items.count)").monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(group.items) {
                        RowView(item: $0, placement: .reviewRequested, now: now, actions: actions.row)
                    }
                }
                notShown(.reviewRequested)
            }
            section(
                .mine, String(localized: "Mine", comment: "Section header"), count: sections.mine.count,
                marked: sections.mine.contains(where: \.isMarked)
            ) {
                if sections.mine.isEmpty {
                    EmptyLine(
                        text: filtering
                            ? emptyTag
                            : String(
                                localized: "No open pull requests of yours in the watched repositories.",
                                comment: "Empty state"))
                }
                ForEach(sections.mine) { RowView(item: $0, placement: .mine, now: now, actions: actions.row) }
                notShown(.authored)
            }
            section(
                .involved, String(localized: "Involved", comment: "Section header"), count: sections.involved.count,
                marked: sections.involved.contains(where: \.isMarked)
            ) {
                if sections.involved.isEmpty {
                    EmptyLine(
                        text: filtering
                            ? emptyTag
                            : String(
                                localized: "Nothing you commented on or reviewed in the last 30 days.",
                                comment: "Empty state"))
                }
                ForEach(sections.involved) { RowView(item: $0, placement: .involved, now: now, actions: actions.row) }
            }
            if !sections.ignored.isEmpty {
                section(
                    .ignored, String(localized: "Ignored", comment: "Section header"), count: sections.ignored.count,
                    marked: false
                ) {
                    ForEach(sections.ignored) { RowView(item: $0, placement: .ignored, now: now, actions: actions.row) }
                }
            }
            if filtering, let tag = model.tagFilter,
                sections.reviewRequested.isEmpty && sections.mine.isEmpty && sections.involved.isEmpty
            {
                Button(String(localized: "Clear Filter", comment: "Empty tag filter button")) { model.tagFilter = nil }
                    .padding(.horizontal, 24)
                    .accessibilityHint(Text(verbatim: tag))
            }
        }
    }

    private var emptyTag: String {
        String(localized: "No pull requests tagged \(model.tagFilter ?? "").", comment: "Empty tag filter")
    }

    @ViewBuilder
    private func notShown(_ role: Role) -> some View {
        let hidden = watch.notShown(role)
        if hidden > 0 {
            Text("+\(hidden) not shown", comment: "More results than the search returned")
                .font(.subheadline).foregroundStyle(Color.textTertiary).padding(.horizontal, 24).padding(.vertical, 4)
        }
    }

    private func section<Content: View>(
        _ section: PopoverModel.Section, _ title: String, count: Int, marked: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = model.expanded.contains(section)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { model.toggle(section) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.caption)
                    Text(verbatim: title)
                    Spacer()
                    Text(verbatim: "\(count)").monospacedDigit()
                    if marked && !isExpanded {
                        Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(Color.accentMarked)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(Text(verbatim: "\(title), \(count)"))
            if isExpanded { content() }
            Divider().padding(.top, 6)
        }
    }
}

struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
    }
}
