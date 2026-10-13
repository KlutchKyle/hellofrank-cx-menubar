#if os(macOS)
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    /// Launch at login defaults to on; register once on the first launch.
    static func applyDefaultOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard Bundle.main.bundleIdentifier != nil,
              !defaults.bool(forKey: SettingsKey.launchAtLoginConfigured) else { return }
        defaults.set(true, forKey: SettingsKey.launchAtLoginConfigured)
        if defaults.bool(forKey: SettingsKey.launchAtLogin) {
            try? set(true)
        }
    }
}
#endif
