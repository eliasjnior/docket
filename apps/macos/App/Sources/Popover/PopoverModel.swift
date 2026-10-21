import DocketActivity
import Foundation
import Observation

/// The popover's own state: filters and which sections are open, kept for the life of the process.
@MainActor
@Observable
final class PopoverModel {
    enum Section: Hashable {
        case reviewRequested
        case mine
        case involved
        case ignored
    }

    var tagFilter: String?
    var repositoryFilter: String?
    var expanded: Set<Section> = [.reviewRequested, .mine]
    var editingTags: WatchedPullRequest?

    func toggle(_ section: Section) {
        if expanded.contains(section) { expanded.remove(section) } else { expanded.insert(section) }
    }

    /// `Escape`: the filter first, then the popover (`docs/05-design.md` §11).
    func clearFilter() -> Bool {
        guard repositoryFilter != nil || tagFilter != nil else { return false }
        if repositoryFilter != nil { repositoryFilter = nil } else { tagFilter = nil }
        return true
    }
}

/// What the popover asks the app to do.
@MainActor
struct PopoverActions {
    var refresh: () -> Void
    var openSettings: () -> Void
    var checkForUpdates: () -> Void
    var quit: () -> Void
    var retry: () -> Void
    var chooseGhLocation: () -> Void
    var dismissBaselineNotice: () -> Void
    var close: () -> Void
    var row: RowActions
}
