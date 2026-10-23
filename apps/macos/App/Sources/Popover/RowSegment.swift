import DocketActivity

/// A list's rows as the list draws them: single rows, and each stack's rows as one block (`docs/05-design.md`
/// §5.3). `Sections` already put a stack's rows together, bottom first.
enum RowSegment: Identifiable {
    case row(WatchedPullRequest)
    case stack(Stack)

    var id: String {
        switch self {
        case .row(let item): item.id
        case .stack(let stack): stack.id
        }
    }

    static func split(_ items: [WatchedPullRequest]) -> [RowSegment] {
        var segments: [RowSegment] = []
        var index = items.startIndex
        while index < items.endIndex {
            let item = items[index]
            if let position = item.stackPosition, position.index == 1, position.count > 1 {
                let end = min(index + position.count, items.endIndex)
                let run = Array(items[index..<end]).prefix { $0.stackPosition?.count == position.count }
                if run.count > 1 {
                    segments.append(.stack(Stack(repository: item.pullRequest.repository, items: Array(run))))
                    index += run.count
                    continue
                }
            }
            segments.append(.row(item))
            index += 1
        }
        return segments
    }
}
