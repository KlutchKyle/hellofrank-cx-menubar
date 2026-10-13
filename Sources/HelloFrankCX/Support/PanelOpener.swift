#if os(macOS)
import AppKit

/// SwiftUI has no API to open a `MenuBarExtra` panel, so this clicks the
/// status item's button. Best effort: if AppKit internals change, it does nothing.
@MainActor
enum PanelOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        let panelIsOpen = NSApp.windows.contains {
            $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtra")
        }
        guard !panelIsOpen else { return }
        for window in NSApp.windows where String(describing: type(of: window)).contains("NSStatusBarWindow") {
            if let button = findStatusButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func findStatusButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findStatusButton(in: subview) { return button }
        }
        return nil
    }
}
#endif
