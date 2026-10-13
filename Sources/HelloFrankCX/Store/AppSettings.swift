#if os(macOS)
import Foundation
import HelloFrankCore

/// UserDefaults keys. Everything here is non-secret; tokens live in the Keychain.
enum SettingsKey {
    static let projectSlug = "linearProjectSlug"
    static let assigneeEmail = "assigneeEmail"
    static let pollIntervalMinutes = "pollIntervalMinutes"
    static let staleThresholdDays = "staleThresholdDays"
    static let cxOnly = "cxOnly"
    static let launchAtLogin = "launchAtLogin"
    static let launchAtLoginConfigured = "launchAtLoginConfigured"

    static func notify(_ kind: QueueEvent.Kind) -> String { "notify.\(kind.rawValue)" }
}

enum AppSettings {
    static let pollIntervalChoices = [1, 2, 5, 15]
    static let defaultPollIntervalMinutes = 2

    static func registerDefaults() {
        var defaults: [String: Any] = [
            SettingsKey.projectSlug: QueueConfig.defaultProjectSlug,
            SettingsKey.assigneeEmail: QueueConfig.defaultAssigneeEmail,
            SettingsKey.pollIntervalMinutes: defaultPollIntervalMinutes,
            SettingsKey.staleThresholdDays: QueueConfig.defaultStaleThresholdDays,
            SettingsKey.cxOnly: false,
            SettingsKey.launchAtLogin: true,
        ]
        for kind in QueueEvent.Kind.allCases {
            defaults[SettingsKey.notify(kind)] = true
        }
        UserDefaults.standard.register(defaults: defaults)
    }

    static var queueConfig: QueueConfig {
        let defaults = UserDefaults.standard
        let slug = defaults.string(forKey: SettingsKey.projectSlug)?.trimmingCharacters(in: .whitespaces) ?? ""
        let email = defaults.string(forKey: SettingsKey.assigneeEmail)?.trimmingCharacters(in: .whitespaces) ?? ""
        let staleDays = defaults.integer(forKey: SettingsKey.staleThresholdDays)
        return QueueConfig(
            projectSlug: slug.isEmpty ? QueueConfig.defaultProjectSlug : slug,
            assigneeEmail: email.isEmpty ? QueueConfig.defaultAssigneeEmail : email,
            staleThresholdDays: staleDays > 0 ? staleDays : QueueConfig.defaultStaleThresholdDays
        )
    }

    /// Never polls more often than once a minute.
    static var pollInterval: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: SettingsKey.pollIntervalMinutes)
        return TimeInterval(max(1, minutes == 0 ? defaultPollIntervalMinutes : minutes) * 60)
    }

    static func isNotificationEnabled(_ kind: QueueEvent.Kind) -> Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.notify(kind))
    }
}
#endif
