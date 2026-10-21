import AppKit

MainActor.assumeIsolated { Snapshots.runIfRequested() }

let delegate = MainActor.assumeIsolated { AppDelegate() }
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
