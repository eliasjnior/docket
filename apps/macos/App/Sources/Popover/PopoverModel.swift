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
    /// Whether the last tab or sub-tab switch went right, so the list slides in from that side.
    private(set) var slidesForward = true

    /// A tab or sub-tab switch that slides the list: the direction is set first, so the outgoing list already
    /// knows which way to leave, then the switch is animated.
    func switchTo(_ section: Section? = nil, triage next: Triage? = nil) {
        let order: [Section] = [.reviewRequested, .mine, .involved, .ignored]
        if let section, section != tab {
            slidesForward = (order.firstIndex(of: section) ?? 0) > (order.firstIndex(of: tab) ?? 0)
        } else if let next, next != triage {
            slidesForward = (Triage.allCases.firstIndex(of: next) ?? 0) > (Triage.allCases.firstIndex(of: triage) ?? 0)
        } else {
            return
        }
        focusedID = nil
        DispatchQueue.main.async {
            withMotion {
                if let section { self.tab = section }
                if let next { self.triage = next }
            }
        }
    }
    /// The row the keyboard focus ring is on (FR-47).
    var focusedID: String?
    /// Repository groups of *Review requested* the user folded.
    var collapsedRepositories: Set<String> = []
    /// *Mine*'s groups folded in the list layout; Draft starts collapsed (spec §7).
    var collapsedMineGroups: Set<MineKind> = [.draft]

    /// Repositories folded inside a *Mine* board column, per column: `<kind>:<owner/name>`.
    var collapsedBoardGroups: Set<String> = []

    static func boardKey(_ kind: MineKind, _ repository: String) -> String { "\(kind.rawValue):\(repository)" }

    func isCollapsed(_ kind: MineKind, _ repository: String) -> Bool {
        collapsedBoardGroups.contains(Self.boardKey(kind, repository))
    }

    func toggle(_ kind: MineKind, repository: String) {
        collapsedBoardGroups.formSymmetricDifference([Self.boardKey(kind, repository)])
    }

    /// In columns, *Involved* folded to a strip, the popover narrower by the column.
    var involvedFolded = false

    /// Stacks folded in *Mine*'s list, by the ID of their bottom pull request.
    var collapsedStacks: Set<String> = []

    func toggle(stack id: String) {
        collapsedStacks.formSymmetricDifference([id])
    }

    func toggle(repository: String) {
        collapsedRepositories.formSymmetricDifference([repository])
    }

    func toggle(_ kind: MineKind) {
        collapsedMineGroups.formSymmetricDifference([kind])
    }

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
