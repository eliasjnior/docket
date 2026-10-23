import SwiftUI

/// A row on its own as a box, the same shape as a stack's block with a quiet border, so rows read apart
/// (`docs/05-design.md` §6.1). A stack's rows share their block instead.
struct RowBox: ViewModifier {
    /// The room on every side of a box: half above and half below, so two boxes are this far apart, and the
    /// list's ends add the other half (`SectionsView.edge`).
    static let inset: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            .padding(.horizontal, Self.inset)
            .padding(.vertical, Self.inset / 2)
    }
}
