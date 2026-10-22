import DocketActivity
import Foundation
import Observation

/// The popover's own state: filters, the tab and the sub-tab, kept for the life of the process.
@MainActor
@Observable
final class PopoverModel {
    enum Section: Hashable {
        case reviewRequested
        case mine
        case involved
        case ignored
    }

    var filter = PopoverFilter()
    var tab: Section = .reviewRequested
    var triage: Triage = .humans
    /// The row the keyboard focus ring is on (FR-47).
    var focusedID: String?
    /// *Mine*'s Draft group in the list layout starts collapsed (spec §7).
    var draftsExpanded = false

    /// `Escape`: the most recently added filter first, then the popover (`docs/05-design.md` §11).
    func clearFilter() -> Bool {
        filter.clearLatest()
    }

    /// A grouped notification's click: that repository alone (FR-59).
    func show(repository: String) {
        filter = PopoverFilter(repositories: [repository])
        tab = .reviewRequested
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
    var launchAtLogin: (Bool) -> Void
    var deliverHeld: () -> Void
    var dismissBaselineNotice: () -> Void
    var close: () -> Void
    var row: RowActions
}
