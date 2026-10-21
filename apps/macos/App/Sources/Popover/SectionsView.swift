import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// The selected tab's rows (`docs/05-design.md` §5.3).
struct SectionsView: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel
    let actions: PopoverActions
    let now: Date

    private var editor: TagEditorBinding {
        TagEditorBinding(model: model, tags: TagStore(configStore: watch.configStore))
    }

    var body: some View {
        let sections = watch.sections(tag: model.tagFilter, repository: model.repositoryFilter)
        let filtering = model.tagFilter != nil || model.repositoryFilter != nil
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
            switch model.tab {
            case .reviewRequested:
                if sections.reviewRequested.isEmpty {
                    EmptyLine(
                        text: filtering
                            ? emptyFilter : String(localized: "No reviews waiting on you.", comment: "Empty state"))
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
                    rows(group.items, .reviewRequested)
                }
                notShown(.reviewRequested)
            case .mine:
                if sections.mine.isEmpty {
                    EmptyLine(
                        text: filtering
                            ? emptyFilter
                            : String(
                                localized: "No open pull requests of yours in the watched repositories.",
                                comment: "Empty state"))
                }
                rows(sections.mine, .mine)
                notShown(.authored)
            case .involved:
                if sections.involved.isEmpty {
                    EmptyLine(
                        text: filtering
                            ? emptyFilter
                            : String(
                                localized: "Nothing you commented on or reviewed in the last 30 days.",
                                comment: "Empty state"))
                }
                rows(sections.involved, .involved)
            case .ignored:
                if sections.ignored.isEmpty {
                    EmptyLine(text: String(localized: "Nothing is ignored.", comment: "Empty state"))
                }
                rows(sections.ignored, .ignored)
            }
            if filtering, model.tab != .ignored {
                Button(String(localized: "Clear Filter", comment: "Filter button")) {
                    model.tagFilter = nil
                    model.repositoryFilter = nil
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
    }

    /// Rows with a separator between each, inset to the text.
    private func rows(_ items: [WatchedPullRequest], _ placement: RowView.Placement) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            RowView(item: item, placement: placement, now: now, actions: actions.row, editor: editor)
            if index < items.count - 1 {
                Divider().padding(.leading, 24).padding(.trailing, 12)
            }
        }
    }

    private var emptyFilter: String {
        if let tag = model.tagFilter {
            return String(localized: "No pull requests tagged \(tag).", comment: "Empty tag filter")
        }
        return String(localized: "Nothing here in \(model.repositoryFilter ?? "").", comment: "Empty repository filter")
    }

    @ViewBuilder
    private func notShown(_ role: Role) -> some View {
        let hidden = watch.notShown(role)
        if hidden > 0 {
            Text("+\(hidden) not shown", comment: "More results than the search returned")
                .font(.subheadline).foregroundStyle(Color.textTertiary).padding(.horizontal, 24).padding(.vertical, 4)
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
