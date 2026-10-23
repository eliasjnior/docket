import DocketActivity
import DocketStores
import SwiftUI

/// *Review requested*, *Mine* and *Involved* side by side (`config.popoverLayout = columns`,
/// `docs/05-design.md` §5.1), each with its own header and scroll. The selected column is where the keyboard
/// moves; *Ignored* replaces *Involved* from its header. *Mine* follows `mineLayout`, a list or a board.
struct ColumnsView: View {
    static let columnWidth: CGFloat = 420
    /// *Involved* folded to a strip.
    static let foldedWidth: CGFloat = 40

    /// *Review requested*, *Mine* and *Involved*: a tab's width each, *Mine* a board's when it is one, *Involved*
    /// a strip when folded, the open ones narrowed together on a screen too small for them.
    static func widths(board: Bool, involvedFolded: Bool) -> [CGFloat] {
        let open = [columnWidth, board ? PopoverView.boardWidth : columnWidth] + (involvedFolded ? [] : [columnWidth])
        let room = (NSScreen.main?.visibleFrame.width ?? 1440) - 42 - (involvedFolded ? foldedWidth : 0)
        let scale = min(1, room / open.reduce(0, +))
        return open.map { ($0 * scale).rounded(.down) } + (involvedFolded ? [foldedWidth] : [])
    }

    let watch: WatchStore
    @Bindable var model: PopoverModel
    let actions: PopoverActions
    let now: Date

    var body: some View {
        let sections = watch.sections(filter: model.filter)
        let widths = Self.widths(board: watch.config.mineLayout == .board, involvedFolded: model.involvedFolded)
        HStack(alignment: .top, spacing: 0) {
            column(
                .reviewRequested, String(localized: "Review requested", comment: "Tab"),
                count: sections.reviewRequestedCount, width: widths[0]
            ) {
                TriageTabs(model: model, sections: sections)
            }
            Divider()
            column(.mine, String(localized: "Mine", comment: "Tab"), count: sections.mine.count, width: widths[1]) {
                EmptyView()
            }
            Divider()
            // The column's own width stays put while this frame grows and clips it, so it slides out like a
            // drawer; laid out at full width at once, its rows drew over *Mine* while the popover grew.
            ZStack(alignment: .topLeading) {
                thirdColumn(sections, widths: widths)
            }
            .frame(width: widths[2], alignment: .topLeading)
            .clipped()
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func thirdColumn(_ sections: Sections, widths: [CGFloat]) -> some View {
        let open = Self.widths(board: watch.config.mineLayout == .board, involvedFolded: false)[2]
        Group {
            if model.involvedFolded {
                foldedStrip(count: sections.involved.count, width: Self.foldedWidth)
                    .transition(.opacity)
            } else if model.tab == .ignored {
                column(
                    .ignored, String(localized: "Ignored", comment: "Tab"), count: sections.ignored.count,
                    width: open
                ) {
                    switchButton(String(localized: "Show Involved", comment: "Column header button"), to: .involved)
                } trailing: {
                    foldButton
                }
                .transition(.opacity)
            } else {
                column(
                    .involved, String(localized: "Involved", comment: "Tab"), count: sections.involved.count,
                    width: open
                ) {
                    if !sections.ignored.isEmpty {
                        switchButton(
                            String(localized: "Ignored (\(sections.ignored.count))", comment: "Column header button"),
                            to: .ignored)
                    }
                } trailing: {
                    foldButton
                }
                .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func column(
        _ section: PopoverModel.Section, _ title: String, count: Int, width: CGFloat,
        @ViewBuilder accessory: () -> some View, @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        let selected = model.tab == section
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(verbatim: title).font(.subheadline.weight(.semibold))
                    CountBadge(count: count)
                    Spacer(minLength: 0)
                    trailing()
                }
                accessory()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(selected ? Color.accent : Color(nsColor: .separatorColor))
                    .frame(height: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { select(section) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? [.isHeader, .isSelected] : .isHeader)
            ScrollView {
                SectionsView(watch: watch, model: model, actions: actions, now: now, section: section)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: width)
        .clipped()
    }

    /// Folds *Involved* to a strip, and the popover narrows by the column.
    private var foldButton: some View {
        Button {
            withMotion { model.involvedFolded = true }
            if model.tab == .involved || model.tab == .ignored { select(.reviewRequested) }
        } label: {
            Image(systemName: "sidebar.right").font(.subheadline).foregroundStyle(Color.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Hide Involved", comment: "Column header button"))
        .accessibilityLabel(Text("Hide Involved", comment: "Column header button"))
    }

    /// *Involved* folded: its name on its side and its count, and a button that opens it again.
    private func foldedStrip(count: Int, width: CGFloat) -> some View {
        Button {
            withMotion { model.involvedFolded = false }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right").font(.subheadline).foregroundStyle(Color.accent)
                CountBadge(count: count)
                Text("Involved", comment: "Tab")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 80)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Show Involved", comment: "Column header button"))
        .accessibilityLabel(Text("Show Involved, \(count)", comment: "Folded column"))
    }

    private func switchButton(_ title: String, to section: PopoverModel.Section) -> some View {
        Button(title) { select(section) }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accent)
    }

    private func select(_ section: PopoverModel.Section) {
        guard model.tab != section else { return }
        withMotion { model.tab = section }
        model.focusedID = nil
    }
}
