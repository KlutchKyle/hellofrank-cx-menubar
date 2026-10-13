#if os(macOS)
import AppKit
import SwiftUI

/// A plain AppKit window for Settings. The SwiftUI `Settings` scene is hard to
/// open from a menu-bar-only app on macOS 13, so the app manages its own.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(QueueStore.shared))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "HelloFrank CX Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
#endif
