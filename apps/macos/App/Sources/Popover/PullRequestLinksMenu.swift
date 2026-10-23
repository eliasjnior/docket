import DocketActivity
import DocketCore
import SwiftUI

/// `PR Links` in a row's context menu: the links in the description, then those in each bot's comments, such
/// as a preview deploy (`docs/05-design.md` §6.5). Disabled when there are none.
struct PullRequestLinksMenu: View {
    let item: WatchedPullRequest
    let open: (URL) -> Void

    var body: some View {
        let description = item.pullRequest.links
        let bots = Dictionary(grouping: item.botLinks) { $0.source ?? "" }
        let botOrder = item.botLinks.compactMap(\.source).reduce(into: [String]()) { order, source in
            if !order.contains(source) { order.append(source) }
        }
        Menu(String(localized: "PR Links", comment: "Row context menu: links in the description and bot comments")) {
            if !description.isEmpty {
                Section(String(localized: "Description", comment: "PR Links section")) {
                    ForEach(description, id: \.url) { link($0) }
                }
            }
            ForEach(botOrder, id: \.self) { source in
                Section(Self.botName(source)) {
                    ForEach(bots[source] ?? [], id: \.url) { link($0) }
                }
            }
        }
        .disabled(description.isEmpty && item.botLinks.isEmpty)
    }

    private func link(_ link: PullRequestLink) -> some View {
        Button(Self.label(link)) { open(link.url) }
    }

    /// The link's text, or its host and path when it has none.
    static func label(_ link: PullRequestLink) -> String {
        if let title = link.title { return "\(title) — \(link.url.host ?? "")" }
        let path = link.url.path == "/" ? "" : link.url.path
        let text = (link.url.host ?? link.url.absoluteString) + path
        return text.count > 70 ? String(text.prefix(69)) + "…" : text
    }

    /// `vercel[bot]` reads as `vercel`.
    static func botName(_ login: String) -> String {
        "@" + (login.hasSuffix("[bot]") ? String(login.dropLast(5)) : login)
    }
}
