import DocketActivity
import SwiftUI

/// *Review requested*'s Humans, Bots, Drafts and Stale (`docs/05-design.md` §5.2), as pills with counts.
struct TriageTabs: View {
    @Bindable var model: PopoverModel
    let sections: Sections

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Triage.allCases, id: \.self) { triage in
                subTab(triage, count: sections.triageCounts[triage] ?? 0)
            }
        }
    }

    private func subTab(_ triage: Triage, count: Int) -> some View {
        let selected = model.triage == triage
        return Button {
            model.switchTo(triage: triage)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: triage.title)
                CountBadge(count: count, selected: selected)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? Color.white : Color.textPrimary)
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Color.accent : Color.fillTag))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text(verbatim: "\(triage.title), \(count)"))
    }
}
