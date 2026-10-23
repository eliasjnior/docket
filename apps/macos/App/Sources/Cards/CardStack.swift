import Foundation
import Observation

/// The cards on screen, newest first (`docs/05-design.md` §8.1).
@MainActor
@Observable
final class CardStack {
    /// Cards beyond this fold into one `N more` line.
    static let visibleLimit = 3

    private(set) var cards: [NotificationCard] = []

    var visible: [NotificationCard] { Array(cards.prefix(Self.visibleLimit)) }
    var hiddenCount: Int { max(0, cards.count - Self.visibleLimit) }

    /// A card for the same notification replaces the one on screen instead of stacking under it.
    func push(_ new: [NotificationCard]) {
        let ids = Set(new.map(\.id))
        cards = new.reversed() + cards.filter { !ids.contains($0.id) }
    }

    func dismiss(_ id: String) {
        cards.removeAll { $0.id == id }
    }

    func dismissAll() {
        cards.removeAll()
    }
}
