#if os(macOS)
import AppKit
import Foundation
import HelloFrankCore
import UserNotifications

/// What a notification needs to act on when clicked; Sendable copy of `userInfo`.
struct NotificationPayload: Sendable {
    var kind: QueueEvent.Kind?
    var ticketID: String?
    var ticketIdentifier: String?
    var ticketURL: URL?
    var prURL: URL?
    var slackChannel: String?
    var slackTS: String?

    init(event: QueueEvent) {
        kind = event.kind
        ticketID = event.ticketID
        ticketIdentifier = event.ticketIdentifier
        ticketURL = event.ticketURL
        prURL = event.prURL
        slackChannel = event.slackChannel
        slackTS = event.slackTS
    }

    init(userInfo: [AnyHashable: Any]) {
        kind = (userInfo["kind"] as? String).flatMap(QueueEvent.Kind.init(rawValue:))
        ticketID = userInfo["ticketID"] as? String
        ticketIdentifier = userInfo["ticketIdentifier"] as? String
        ticketURL = (userInfo["ticketURL"] as? String).flatMap(URL.init(string:))
        prURL = (userInfo["prURL"] as? String).flatMap(URL.init(string:))
        slackChannel = userInfo["slackChannel"] as? String
        slackTS = userInfo["slackTS"] as? String
    }

    var userInfo: [String: String] {
        var info: [String: String] = [:]
        info["kind"] = kind?.rawValue
        info["ticketID"] = ticketID
        info["ticketIdentifier"] = ticketIdentifier
        info["ticketURL"] = ticketURL?.absoluteString
        info["prURL"] = prURL?.absoluteString
        info["slackChannel"] = slackChannel
        info["slackTS"] = slackTS
        return info
    }
}

/// Native notifications, including Approve and Decline on fix proposals.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let proposalCategory = "FIX_PROPOSAL"
    static let approveAction = "APPROVE"
    static let declineAction = "DECLINE"

    private weak var store: QueueStore?

    /// `UNUserNotificationCenter` crashes outside an app bundle, e.g. when
    /// the executable is run straight from `swift run`.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func configure(store: QueueStore) {
        self.store = store
        guard let center else { return }
        center.delegate = self
        let approve = UNNotificationAction(identifier: Self.approveAction, title: "✅ Approve", options: [])
        let decline = UNNotificationAction(identifier: Self.declineAction, title: "❌ Decline", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.proposalCategory,
                actions: [approve, decline],
                intentIdentifiers: [],
                options: []
            ),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ events: [QueueEvent], staleThresholdDays: Int) {
        guard let center else { return }
        for event in events where AppSettings.isNotificationEnabled(event.kind) {
            let content = UNMutableNotificationContent()
            let id = event.ticketIdentifier ?? "ticket"
            let titled = event.ticketTitle.map { "\(id) · \($0)" } ?? id
            switch event.kind {
            case .fixProposal:
                content.title = "Fix proposed: \(titled)"
                content.body = event.detail.map { "Root cause: \($0)" } ?? "Approve or decline the proposal."
                content.categoryIdentifier = Self.proposalCategory
            case .prodDebug:
                content.title = "Debugged: \(id)"
                content.body = event.detail.map { "Root cause: \($0)" } ?? (event.ticketTitle ?? "")
            case .fixPR:
                content.title = "Draft PR ready: \(id)"
                content.body = event.ticketTitle ?? ""
            case .question:
                content.title = "Question on \(id)"
                content.body = event.detail ?? event.ticketTitle ?? ""
            case .newTicket:
                content.title = "New ticket: \(titled)"
            case .stale:
                let count = event.count ?? 1
                content.title = count == 1
                    ? "\(id) has gone \(staleThresholdDays)+ days quiet"
                    : "\(count) tickets have gone \(staleThresholdDays)+ days quiet"
            }
            content.sound = .default
            content.userInfo = NotificationPayload(event: event).userInfo
            center.add(UNNotificationRequest(identifier: event.key, content: content, trigger: nil))
        }
    }

    private func notifyFailure(_ message: String, ticketIdentifier: String?) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Couldn't update \(ticketIdentifier ?? "the proposal")"
        content.body = message
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        let action = response.actionIdentifier
        completionHandler()
        Task { @MainActor in
            await self.handle(action: action, payload: payload)
        }
    }

    private func handle(action: String, payload: NotificationPayload) async {
        guard let store else { return }
        switch action {
        case Self.approveAction, Self.declineAction:
            guard let channel = payload.slackChannel, let ts = payload.slackTS else { return }
            let decision: ProposalDecision = action == Self.approveAction ? .approve : .decline
            let ok = await store.react(decision, channel: channel, ts: ts)
            if !ok, case .failed(_, let message)? = store.proposalActions[ts] {
                notifyFailure(message, ticketIdentifier: payload.ticketIdentifier)
            }
        case UNNotificationDefaultActionIdentifier:
            open(payload, store: store)
        default:
            break
        }
    }

    private func open(_ payload: NotificationPayload, store: QueueStore) {
        let ticketURL = payload.ticketURL ?? payload.ticketIdentifier.flatMap(store.linearURL(for:))
        switch payload.kind {
        case .fixProposal?, .stale?, nil:
            store.focus(ticketID: payload.ticketID)
            PanelOpener.open()
        case .fixPR?:
            if let url = payload.prURL ?? ticketURL { NSWorkspace.shared.open(url) }
        case .prodDebug?, .question?, .newTicket?:
            if let ticketURL {
                NSWorkspace.shared.open(ticketURL)
            } else {
                store.focus(ticketID: payload.ticketID)
                PanelOpener.open()
            }
        }
    }
}
#endif
