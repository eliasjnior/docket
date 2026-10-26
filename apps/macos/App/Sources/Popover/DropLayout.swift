import SwiftUI

/// A row's detail line as one pass: each item measured once, then the highest `DropRank` left out first —
/// the last of a rank before the earlier ones — until the rest fits (`docs/05-design.md` §6.1). It replaced a
/// `ViewThatFits` over six whole versions of the line, which measured each of them and made switching tabs slow.
/// When only the items that never leave are left and they still do not fit, the `DropShrinks` ones give up the
/// rest of the width and truncate, so the line never grows past what it is offered.
struct DropLayout: Layout {
    var spacing: CGFloat = 6

    struct Cache {
        var sizes: [CGSize]
        var ranks: [Int]
        var shrinks: [Bool]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) }, ranks: subviews.map { $0[DropRank.self] },
            shrinks: subviews.map { $0[DropShrinks.self] })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let widths = widths(fitting: proposal.width ?? .infinity, cache: cache)
        return CGSize(
            width: total(of: widths), height: widths.keys.map { cache.sizes[$0].height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let widths = widths(fitting: bounds.width, cache: cache)
        var x = bounds.minX
        for index in subviews.indices {
            let size = cache.sizes[index]
            guard let width = widths[index] else {
                // Out of sight past the row's trailing edge, which clips it.
                subviews[index].place(
                    at: CGPoint(x: bounds.maxX + 10_000, y: bounds.midY), anchor: .leading,
                    proposal: ProposedViewSize(size))
                continue
            }
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
        }
    }

    /// The width of each item that is kept.
    private func widths(fitting width: CGFloat, cache: Cache) -> [Int: CGFloat] {
        let kept = kept(width: width, cache: cache)
        var widths = Dictionary(uniqueKeysWithValues: kept.map { ($0, cache.sizes[$0].width) })
        var overflow = total(of: widths) - width
        for index in kept where overflow > 0 && cache.shrinks[index] {
            let given = min(overflow, max(0, cache.sizes[index].width - Self.shrunkMinimum))
            widths[index, default: 0] -= given
            overflow -= given
        }
        return widths
    }

    /// Enough for a shrunk item to keep its leading mark and an ellipsis.
    private static let shrunkMinimum: CGFloat = 40

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

    private func total(of widths: [Int: CGFloat]) -> CGFloat {
        widths.values.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
    }
}

/// How early an item leaves a `DropLayout` that is too narrow: `0` never, higher first.
struct DropRank: LayoutValueKey {
    static let defaultValue = 0
}

/// An item that truncates rather than push a `DropLayout` past its width once nothing else can leave.
struct DropShrinks: LayoutValueKey {
    static let defaultValue = false
}
