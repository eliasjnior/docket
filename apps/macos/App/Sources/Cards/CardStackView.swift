import SwiftUI

/// The cards, newest on top, with a footer once there is more than one (`docs/05-design.md` §8.1).
struct CardStackView: View {
    static let cardWidth: CGFloat = 360
    /// Room around the cards for their shadow.
    static let margin: CGFloat = 14

    let stack: CardStack
    let actions: CardActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(stack.visible) { card in
                NotificationCardView(card: card, actions: actions)
                    .transition(
                        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            }
            if stack.cards.count > 1 { footer }
        }
        .padding(Self.margin)
        .frame(width: Self.cardWidth + 2 * Self.margin, alignment: .topTrailing)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: stack.cards.map(\.id))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if stack.hiddenCount > 0 {
                Button(String(localized: "\(stack.hiddenCount) more in Docket", comment: "Card stack footer")) {
                    actions.showMore()
                }
            }
            Button(String(localized: "Dismiss All", comment: "Card stack footer"), action: actions.dismissAll)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
    }
}
