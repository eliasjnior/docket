import DocketActivity
import Foundation

/// What a row can do; the popover supplies it, so rows stay plain views.
@MainActor
struct RowActions {
    var open: (URL) -> Void
    var copy: (String) -> Void
    var filterRepository: (String) -> Void
    var setMute: (WatchedPullRequest, MuteChoice?) -> Void
    var setIgnored: (WatchedPullRequest, Bool) -> Void
    /// Opened from Docket, or *Mark All as Seen* (spec §4).
    var markSeen: ([String]) -> Void

    enum MuteChoice {
        case reminders
        case all
    }

    /// A click, `Return` or *Open in Browser*: the page, and the row is seen.
    func open(_ item: WatchedPullRequest) {
        open(item.pullRequest.url)
        markSeen([item.id])
    }
}
