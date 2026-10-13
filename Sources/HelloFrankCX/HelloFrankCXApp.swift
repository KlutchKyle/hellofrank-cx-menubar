#if os(macOS)
import AppKit
import HelloFrankCore
import SwiftUI

@main
struct HelloFrankCXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = QueueStore.shared

    var body: some Scene {
        MenuBarExtra {
            QueuePanel()
                .environmentObject(store)
        } label: {
            MenuBarLabel(count: store.badgeCount, warning: store.hasWarning)
        }
        .menuBarExtraStyle(.window)
    }
}

/// `tray` when nothing needs Kyle, `tray.full` plus the count when something does.
struct MenuBarLabel: View {
    let count: Int
    let warning: Bool

    var body: some View {
        let text = [count > 0 ? "\(count)" : nil, warning ? "⚠︎" : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        HStack(spacing: 3) {
            Image(systemName: count > 0 ? "tray.full" : "tray")
            if !text.isEmpty {
                Text(text)
            }
        }
        .accessibilityLabel(
            count > 0 ? "HelloFrank CX, \(count) waiting on you" : "HelloFrank CX"
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        QueueStore.shared.start()
        LaunchAtLogin.applyDefaultOnFirstLaunch()
        if !QueueStore.shared.hasLinearKey {
            SettingsWindow.show()
        }
    }
}
#else
/// The app itself needs macOS; on other platforms only HelloFrankCore builds.
@main
enum HelloFrankCXUnsupported {
    static func main() {
        print("HelloFrank CX is a macOS menu bar app.")
    }
}
#endif
