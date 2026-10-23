import AppKit
import SwiftUI

/// The popover's one animation for folds, the *Involved* strip and tab switches (`docs/05-design.md` §10.4),
/// left out under Reduce Motion.
@MainActor
func withMotion(_ change: () -> Void) {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        change()
    } else {
        withAnimation(.easeInOut(duration: 0.22), change)
    }
}
