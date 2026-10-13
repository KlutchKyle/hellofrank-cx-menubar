#if os(macOS)
import AppKit
import Foundation
import HelloFrankCore
import Network
import os

/// State of an Approve or Decline the user started from the app.
enum ProposalAction: Equatable {
    case sending(ProposalDecision)
    case failed(ProposalDecision, String)
}

/// Polls Linear and Slack, merges them into the queue, detects changes and
/// publishes everything the menu bar and panel show.
@MainActor
final class QueueStore: ObservableObject {
    static let shared = QueueStore()

    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var linearError: String?
    @Published private(set) var slackError: String?
    @Published private(set) var consecutiveFailures = 0
    @Published private(set) var hasLinearKey = false
    @Published private(set) var hasSlackToken = false
    /// Keyed by the proposal's Slack `ts`.
    @Published private(set) var proposalActions: [String: ProposalAction] = [:]
    /// Row to scroll to and highlight, e.g. after clicking a notification.
    @Published var focusedTicketID: String?

    static let failuresBeforeBackoff = 3
    static let backoffInterval: TimeInterval = 15 * 60
    static let panelRefreshAge: TimeInterval = 30

    let notifier = Notifier()

    private let stateFile = StateFile.standard()
    private var persisted: PersistedState
    private let logger = Logger(subsystem: "ai.hellofrank.cx-menubar", category: "queue")

    private var linearKey: String?
    private var slackToken: String?
    private var issues: [LinearIssue] = []
    private var hasFreshLinearData = false
    private var slackMessages: [SlackRoutineMessage]?
    private var viewerID: String?
    private var slackIdentity: SlackIdentity?
    private var slackChannel: String?
    /// Reactions added from the app that Slack hasn't echoed back yet, by `ts`.
    private var localReactions: [String: String] = [:]

    private var lastAttempt: Date?
    private var timer: Timer?
    private var isAsleep = false
    private var isOnline = true
    private let pathMonitor = NWPathMonitor()
    private var started = false

    private init() {
        AppSettings.registerDefaults()
        persisted = stateFile.load() ?? PersistedState()
        tickets = persisted.cachedTickets
        lastUpdated = persisted.cachedAt
        reloadCredentials()
    }

    // MARK: Derived

    var badgeCount: Int { QueueBuilder.badgeCount(tickets, now: Date()) }
    var needsYou: [Ticket] { QueueBuilder.needsYou(tickets, now: Date()) }
    /// Shown on the icon after repeated failures, until a poll succeeds.
    var hasWarning: Bool { consecutiveFailures >= Self.failuresBeforeBackoff }

    private var effectiveInterval: TimeInterval {
        hasWarning ? max(AppSettings.pollInterval, Self.backoffInterval) : AppSettings.pollInterval
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        notifier.configure(store: self)
        observeSystem()
        // A short tick re-reads the interval setting, so changes apply without a restart.
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await refresh() }
    }

    private func tick() {
        guard !isAsleep, isOnline, !isRefreshing, hasLinearKey else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < effectiveInterval { return }
        Task { await refresh() }
    }

    /// Called when the panel opens.
    func refreshIfStale() {
        guard !isRefreshing else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.panelRefreshAge { return }
        Task { await refresh() }
    }

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isAsleep = true }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isAsleep = false
                // Give the network a moment to come back, then poll once.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.refresh()
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "ai.hellofrank.cx-menubar.network"))
    }

    private func networkChanged(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack && !isAsleep { Task { await refresh() } }
    }

    // MARK: Credentials and settings

    private func reloadCredentials() {
        linearKey = Keychain.read(.linearAPIKey)
        slackToken = Keychain.read(.slackUserToken)
        hasLinearKey = linearKey != nil
        hasSlackToken = slackToken != nil
    }

    /// After a token is saved, replaced or removed in Settings.
    func credentialsChanged() {
        reloadCredentials()
        viewerID = nil
        slackIdentity = nil
        slackChannel = nil
        consecutiveFailures = 0
        if !hasSlackToken {
            slackMessages = nil
            slackError = nil
        }
        if !hasLinearKey {
            issues = []
            hasFreshLinearData = false
            tickets = []
            linearError = nil
        } else {
            rebuild()
        }
        Task { await refresh() }
    }

    /// After a queue setting changes. Project or assignee changes need a fetch;
    /// the stale threshold only needs a rebuild.
    func settingsChanged(refetch: Bool) {
        if refetch {
            Task { await refresh() }
        } else {
            rebuild()
        }
    }

    // MARK: Polling

    func refresh() async {
        guard !isRefreshing, let linearKey else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastAttempt = Date()

        let config = AppSettings.queueConfig
        let linearClient = LinearClient(apiKey: linearKey)
        let slackClient = slackToken.map { SlackClient(token: $0) }
        let needViewer = viewerID == nil
        let identity = slackIdentity
        let channel = slackChannel

        async let linearTask = Self.fetchLinear(client: linearClient, config: config, needViewer: needViewer)
        async let slackTask = Self.fetchSlack(client: slackClient, identity: identity, channel: channel)
        let (linearResult, slackResult) = await (linearTask, slackTask)

        var succeeded = Set<QueueEvent.Source>()
        var failed = false

        switch linearResult {
        case .success(let fetch):
            issues = fetch.issues
            if let viewer = fetch.viewer { viewerID = viewer.id }
            hasFreshLinearData = true
            linearError = nil
            succeeded.insert(.linear)
        case .failure(let error):
            linearError = Self.describe(error)
            logger.error("Linear poll failed: \(Self.describe(error), privacy: .public)")
            failed = true
        }

        switch slackResult {
        case .none:
            slackMessages = nil
            slackError = nil
        case .success(let fetch)?:
            slackIdentity = fetch.identity
            slackChannel = fetch.channel
            slackMessages = fetch.messages
            reconcileLocalReactions()
            slackError = nil
            succeeded.insert(.slack)
        case .failure(let error)?:
            slackError = Self.describe(error)
            logger.error("Slack poll failed: \(Self.describe(error), privacy: .public)")
            if let apiError = error as? APIError, apiError.isAuthFailure {
                slackIdentity = nil
                slackChannel = nil
            }
            failed = true
        }

        consecutiveFailures = failed ? consecutiveFailures + 1 : 0

        guard hasFreshLinearData else { return }
        rebuild()
        if succeeded.contains(.linear) { lastUpdated = Date() }

        let now = Date()
        let events = QueueEventPlanner.events(tickets: tickets, issues: issues, slackMessages: slackMessages, now: now)
        let newEvents = ChangeDetector.process(
            events: events, state: &persisted.seen, succeededSources: succeeded, now: now
        )
        notifier.deliver(newEvents, staleThresholdDays: config.staleThresholdDays)
        persist()
    }

    private struct LinearFetch: Sendable {
        var issues: [LinearIssue]
        var viewer: LinearViewer?
    }

    private struct SlackFetch: Sendable {
        var identity: SlackIdentity
        var channel: String
        var messages: [SlackRoutineMessage]
    }

    private nonisolated static func fetchLinear(
        client: LinearClient, config: QueueConfig, needViewer: Bool
    ) async -> Result<LinearFetch, Error> {
        do {
            let viewer = needViewer ? try await client.viewer() : nil
            let issues = try await client.fetchQueue(
                projectSlug: config.projectSlug, assigneeEmail: config.assigneeEmail
            )
            return .success(LinearFetch(issues: issues, viewer: viewer))
        } catch {
            return .failure(error)
        }
    }

    private nonisolated static func fetchSlack(
        client: SlackClient?, identity: SlackIdentity?, channel: String?
    ) async -> Result<SlackFetch, Error>? {
        guard let client else { return nil }
        do {
            var resolvedIdentity = identity
            if resolvedIdentity == nil { resolvedIdentity = try await client.authTest() }
            guard let resolvedIdentity else { throw APIError.decoding(service: "Slack") }
            var resolvedChannel = channel
            if resolvedChannel == nil { resolvedChannel = try await client.openSelfDM(userID: resolvedIdentity.userID) }
            guard let resolvedChannel else { throw APIError.decoding(service: "Slack") }
            let messages = try await client.fetchRoutineMessages(channel: resolvedChannel, now: Date())
            return .success(SlackFetch(identity: resolvedIdentity, channel: resolvedChannel, messages: messages))
        } catch {
            return .failure(error)
        }
    }

    private func rebuild() {
        guard hasFreshLinearData else { return }
        let messages = slackMessages.map { messages in
            messages.map { message -> SlackRoutineMessage in
                guard let reaction = localReactions[message.ts] else { return message }
                var copy = message
                copy.reactions.insert(reaction)
                return copy
            }
        }
        tickets = QueueBuilder.build(
            issues: issues,
            slackMessages: messages,
            viewerID: viewerID,
            config: AppSettings.queueConfig,
            now: Date()
        )
    }

    /// Drops optimistic reactions once Slack reflects them or the routine has moved on.
    private func reconcileLocalReactions() {
        let byTS = Dictionary((slackMessages ?? []).map { ($0.ts, $0) }, uniquingKeysWith: { first, _ in first })
        localReactions = localReactions.filter { ts, reaction in
            guard let message = byTS[ts] else { return false }
            return !message.reactions.contains(reaction)
                && !message.reactions.contains(SlackReaction.implementing)
                && !message.reactions.contains(SlackReaction.declined)
        }
    }

    private func persist() {
        persisted.cachedTickets = tickets
        persisted.cachedAt = lastUpdated
        do {
            try stateFile.save(persisted)
        } catch {
            logger.error("Could not save state: \((error as NSError).code, privacy: .public)")
        }
    }

    // MARK: Approval

    /// Adds Kyle's ✅ or ❌ to the proposal message. Fix Approvals does the rest.
    /// On failure the row stays in Waiting on you with the error shown; no silent retry.
    @discardableResult
    func react(_ decision: ProposalDecision, channel: String, ts: String) async -> Bool {
        if case .sending? = proposalActions[ts] { return false }
        guard let slackToken else {
            proposalActions[ts] = .failed(decision, "Add a Slack token in Settings")
            return false
        }
        proposalActions[ts] = .sending(decision)
        do {
            try await SlackClient(token: slackToken).addReaction(decision.reactionName, channel: channel, ts: ts)
            localReactions[ts] = decision.reactionName
            proposalActions[ts] = nil
            rebuild()
            persist()
            return true
        } catch {
            proposalActions[ts] = .failed(decision, Self.describe(error))
            logger.error("reactions.add failed: \(Self.describe(error), privacy: .public)")
            return false
        }
    }

    // MARK: Settings → Test connection

    func testConnections() async -> [String] {
        reloadCredentials()
        var lines: [String] = []
        if let linearKey {
            do {
                let viewer = try await LinearClient(apiKey: linearKey).viewer()
                lines.append("Linear: connected as \(viewer.email) (\(viewer.name))")
            } catch {
                lines.append("Linear: \(Self.describe(error))")
            }
        } else {
            lines.append("Linear: no API key saved")
        }
        if let slackToken {
            do {
                let identity = try await SlackClient(token: slackToken).authTest()
                lines.append("Slack: connected as @\(identity.user)" + (identity.team.map { " in \($0)" } ?? ""))
            } catch {
                lines.append("Slack: \(Self.describe(error))")
            }
        } else {
            lines.append("Slack: no user token saved")
        }
        return lines
    }

    // MARK: Helpers

    func ticket(id: String?) -> Ticket? {
        guard let id else { return nil }
        return tickets.first { $0.id == id }
    }

    /// Linear URL for an identifier, built from any known ticket URL
    /// (`https://linear.app/<workspace>/issue/HEL-1234/...`).
    func linearURL(for identifier: String) -> URL? {
        if let ticket = tickets.first(where: { $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame }) {
            return ticket.url
        }
        guard let sample = tickets.first?.url else { return nil }
        let parts = sample.pathComponents
        guard let index = parts.firstIndex(of: "issue") else { return nil }
        var components = URLComponents(url: sample, resolvingAgainstBaseURL: false)
        components?.path = (parts[1...index] + [identifier]).reduce("") { $0 + "/" + $1 }
        return components?.url
    }

    func focus(ticketID: String?) {
        focusedTicketID = ticketID
    }

    static func describe(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Error"
        }
        return "Error \((error as NSError).code)"
    }
}
#endif
