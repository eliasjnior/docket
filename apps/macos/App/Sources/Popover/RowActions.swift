import DocketActivity
import Foundation

/// What a row can do; the popover supplies it, so rows stay plain views.
@MainActor
struct RowActions {
    var open: (URL) -> Void
    var copy: (String) -> Void
    var filterRepository: (String) -> Void
    var filterTag: (String) -> Void
    var editTags: (WatchedPullRequest) -> Void
    var setMute: (WatchedPullRequest, MuteChoice?) -> Void
    var setIgnored: (WatchedPullRequest, Bool) -> Void

    enum MuteChoice {
        case reminders
        case all
    }
}
