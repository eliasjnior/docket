import AppKit
import SwiftUI

/// The app icon as a SwiftUI view, read from the app's asset catalog. `NSApp.applicationIconImage` goes through
/// the icon cache, which can still hold a generic icon for a menu bar app right after its icon changes.
struct AppIconView: View {
    var size: CGFloat = 64

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private static var icon: NSImage {
        NSImage(named: "AppIcon") ?? Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage
    }
}
