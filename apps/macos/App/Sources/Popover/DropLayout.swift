import SwiftUI

/// A row's detail line as one pass: each item measured once, then the highest `DropRank` left out first —
/// the last of a rank before the earlier ones — until the rest fits (`docs/05-design.md` §6.1). It replaced a
/// `ViewThatFits` over six whole versions of the line, which measured each of them and made switching tabs slow.
struct DropLayout: Layout {
    var spacing: CGFloat = 6

    struct Cache {
        var sizes: [CGSize]
        var ranks: [Int]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) }, ranks: subviews.map { $0[DropRank.self] })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let kept = kept(width: proposal.width ?? .infinity, cache: cache)
        return CGSize(width: width(of: kept, cache: cache), height: kept.map { cache.sizes[$0].height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let kept = Set(kept(width: bounds.width, cache: cache))
        var x = bounds.minX
        for index in subviews.indices {
            let size = cache.sizes[index]
            guard kept.contains(index) else {
                // Out of sight past the row's trailing edge, which clips it.
                subviews[index].place(
                    at: CGPoint(x: bounds.maxX + 10_000, y: bounds.midY), anchor: .leading,
                    proposal: ProposedViewSize(size))
                continue
            }
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }

    /// The indices that fit, in order.
    private func kept(width: CGFloat, cache: Cache) -> [Int] {
        var kept = Array(cache.sizes.indices)
        while self.width(of: kept, cache: cache) > width {
            let droppable = kept.filter { cache.ranks[$0] > 0 }
            guard let drop = droppable.max(by: { (cache.ranks[$0], $0) < (cache.ranks[$1], $1) }) else { break }
            kept.removeAll { $0 == drop }
        }
        return kept
    }

    private func width(of indices: [Int], cache: Cache) -> CGFloat {
        indices.reduce(0) { $0 + cache.sizes[$1].width } + spacing * CGFloat(max(0, indices.count - 1))
    }
}

/// How early an item leaves a `DropLayout` that is too narrow: `0` never, higher first.
struct DropRank: LayoutValueKey {
    static let defaultValue = 0
}
