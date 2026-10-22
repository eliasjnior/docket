import DocketActivity
import DocketStores
import SwiftUI

/// The sections as a segmented control: the label centred, its count in a circle at the trailing edge
/// (`docs/05-design.md` §5.3). *Ignored* appears only while something is ignored.
struct TabBar: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel

    var body: some View {
        let sections = watch.sections(filter: model.filter)
        SegmentLayout(spacing: 2) {
            segment(
                .reviewRequested, String(localized: "Review requested", comment: "Tab"), sections.reviewRequestedCount)
            segment(.mine, String(localized: "Mine", comment: "Tab"), sections.mine.count)
            segment(.involved, String(localized: "Involved", comment: "Tab"), sections.involved.count)
            if !sections.ignored.isEmpty || model.tab == .ignored {
                segment(.ignored, String(localized: "Ignored", comment: "Tab"), sections.ignored.count)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.fillTag))
        .padding(.horizontal, 16)
    }

    private func segment(_ section: PopoverModel.Section, _ title: String, _ count: Int) -> some View {
        let selected = model.tab == section
        return Button {
            model.tab = section
            model.focusedID = nil
        } label: {
            ZStack {
                Text(verbatim: title)
                    .lineLimit(1)
                    .padding(.horizontal, 30)
                HStack {
                    Spacer(minLength: 0)
                    CountBadge(count: count, selected: selected)
                }
                .padding(.trailing, 6)
            }
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accent : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text(verbatim: "\(title), \(count)"))
    }
}

/// A count in a circle, the number centred in it; white with accent digits on a selected tab.
struct CountBadge: View {
    let count: Int
    var selected = false

    var body: some View {
        Text(verbatim: count > 999 ? "999+" : "\(count)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(selected ? Color.accent : Color.textPrimary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(selected ? Color.white : Color.fillBadge))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// Lays segments out on one line: each gets its ideal width plus an equal share of what is left, and all
/// shrink in proportion when they do not fit, so a long label never pushes the others off.
struct SegmentLayout: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = ideals.map(\.height).max() ?? 0
        let natural = ideals.map(\.width).reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: proposal.width ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = Self.widths(
            ideals: subviews.map { $0.sizeThatFits(.unspecified).width },
            available: bounds.width - spacing * CGFloat(max(subviews.count - 1, 0)))
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    static func widths(ideals: [CGFloat], available: CGFloat) -> [CGFloat] {
        let total = ideals.reduce(0, +)
        guard !ideals.isEmpty, total > 0 else { return ideals }
        if total <= available {
            let extra = (available - total) / CGFloat(ideals.count)
            return ideals.map { $0 + extra }
        }
        return ideals.map { $0 * available / total }
    }
}
