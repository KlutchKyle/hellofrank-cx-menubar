#if os(macOS)
import AppKit
import HelloFrankCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: QueueStore
    @AppStorage(SettingsKey.projectSlug) private var projectSlug = QueueConfig.defaultProjectSlug
    @AppStorage(SettingsKey.assigneeEmail) private var assigneeEmail = QueueConfig.defaultAssigneeEmail
    @AppStorage(SettingsKey.pollIntervalMinutes) private var pollMinutes = AppSettings.defaultPollIntervalMinutes
    @AppStorage(SettingsKey.staleThresholdDays) private var staleDays = QueueConfig.defaultStaleThresholdDays
    @AppStorage(SettingsKey.cxOnly) private var cxOnly = false
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = true
    @State private var launchError: String?
    @State private var testLines: [String] = []
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                SecretRow(
                    title: "Linear API key",
                    account: .linearAPIKey,
                    hint: "Linear → Settings → Security & access → Personal API keys"
                )
                SecretRow(
                    title: "Slack user token",
                    account: .slackUserToken,
                    hint: "The xoxp-… User OAuth Token from your Slack app's OAuth & Permissions page"
                )
                HStack {
                    Button("Test connection") {
                        testing = true
                        Task {
                            testLines = await store.testConnections()
                            testing = false
                        }
                    }
                    .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                ForEach(testLines, id: \.self) { line in
                    Text(line).font(.callout).textSelection(.enabled)
                }
            } header: {
                Text("Credentials")
            } footer: {
                Text("Stored only in your Keychain.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Queue") {
                TextField("Linear project slug", text: $projectSlug)
                    .onSubmit { store.settingsChanged(refetch: true) }
                TextField("Assignee email", text: $assigneeEmail)
                    .onSubmit { store.settingsChanged(refetch: true) }
                Picker("Poll every", selection: $pollMinutes) {
                    ForEach(AppSettings.pollIntervalChoices, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                Stepper("Stale after \(staleDays) days", value: $staleDays, in: 1...90)
                    .onChange(of: staleDays) { _ in store.settingsChanged(refetch: false) }
                Toggle("Show CX tickets only", isOn: $cxOnly)
            }

            Section("Notifications") {
                ForEach(QueueEvent.Kind.allCases, id: \.self) { kind in
                    NotificationToggle(kind: kind)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            launchError = nil
                        } catch {
                            launchError = "Couldn't change launch at login (\((error as NSError).code))"
                        }
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 660)
        .onDisappear { store.settingsChanged(refetch: true) }
    }
}

private struct NotificationToggle: View {
    let kind: QueueEvent.Kind
    @AppStorage private var enabled: Bool

    init(kind: QueueEvent.Kind) {
        self.kind = kind
        _enabled = AppStorage(wrappedValue: true, SettingsKey.notify(kind))
    }

    var body: some View {
        Toggle(kind.settingsTitle, isOn: $enabled)
    }
}

/// Shows whether a token is saved, never its value.
private struct SecretRow: View {
    let title: String
    let account: Keychain.Account
    let hint: String

    @EnvironmentObject private var store: QueueStore
    @State private var isEditing = false
    @State private var draft = ""
    @State private var error: String?

    private var isSaved: Bool {
        account == .linearAPIKey ? store.hasLinearKey : store.hasSlackToken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if !isEditing {
                    Text(isSaved ? "Saved" : "Not set")
                        .foregroundStyle(isSaved ? Color.green : Color.secondary)
                    Button(isSaved ? "Replace" : "Add") {
                        draft = ""
                        error = nil
                        isEditing = true
                    }
                    if isSaved {
                        Button("Remove", role: .destructive) { remove() }
                    }
                }
            }
            if isEditing {
                HStack {
                    SecureField(title, text: $draft)
                        .onSubmit(save)
                    Button("Paste") {
                        draft = NSPasteboard.general.string(forType: .string) ?? ""
                    }
                    Button("Save", action: save)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") {
                        draft = ""
                        isEditing = false
                    }
                }
            }
            Text(hint).font(.caption).foregroundStyle(.secondary)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if account == .slackUserToken && !value.hasPrefix("xoxp-") {
            error = "Slack user tokens start with xoxp-"
            return
        }
        do {
            try Keychain.save(value, for: account)
            draft = ""
            error = nil
            isEditing = false
            store.credentialsChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try Keychain.delete(account)
            error = nil
            store.credentialsChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
