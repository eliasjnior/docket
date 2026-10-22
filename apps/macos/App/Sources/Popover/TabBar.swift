import DocketActivity
import DocketStores
import SwiftUI

/// The sections as a segmented control of equal segments, each with its label and count circle centred together
/// (`docs/05-design.md` §5.3). *Ignored* appears only while something is ignored.
struct TabBar: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel

    var body: some View {
        let sections = watch.sections(filter: model.filter)
        HStack(spacing: 2) {
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
            HStack(spacing: 5) {
                Text(verbatim: title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                CountBadge(count: count, selected: selected)
            }
            .padding(.horizontal, 2)
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 28)
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
