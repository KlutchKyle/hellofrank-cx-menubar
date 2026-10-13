import Foundation

/// Something that may deserve a notification.
public struct QueueEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case fixProposal
        case prodDebug
        case fixPR
        case question
        case newTicket
        case stale

        /// Name shown next to the per-type toggle in Settings.
        public var settingsTitle: String {
            switch self {
            case .fixProposal: return "Fix proposed"
            case .prodDebug: return "Debugged"
            case .fixPR: return "Draft PR ready"
            case .question: return "Question for you"
            case .newTicket: return "New ticket"
            case .stale: return "Daily stale digest"
            }
        }
    }

    public enum Source: String, Codable, Sendable {
        case linear
        case slack
    }

    /// Stable dedupe key: Linear comment ID, Slack `ts`, or issue ID.
    public var key: String
    public var kind: Kind
    public var source: Source
    public var ticketID: String?
    public var ticketIdentifier: String?
    public var ticketTitle: String?
    public var ticketURL: URL?
    public var prURL: URL?
    public var slackChannel: String?
    public var slackTS: String?
    /// Root cause line or the question text.
    public var detail: String?
    /// For the stale digest: how many tickets went quiet.
    public var count: Int?

    public init(
        key: String,
        kind: Kind,
        source: Source,
        ticketID: String? = nil,
        ticketIdentifier: String? = nil,
        ticketTitle: String? = nil,
        ticketURL: URL? = nil,
        prURL: URL? = nil,
        slackChannel: String? = nil,
        slackTS: String? = nil,
        detail: String? = nil,
        count: Int? = nil
    ) {
        self.key = key
        self.kind = kind
        self.source = source
        self.ticketID = ticketID
        self.ticketIdentifier = ticketIdentifier
        self.ticketTitle = ticketTitle
        self.ticketURL = ticketURL
        self.prURL = prURL
        self.slackChannel = slackChannel
        self.slackTS = slackTS
        self.detail = detail
        self.count = count
    }
}

public enum QueueEventPlanner {
    /// Every event the current data could produce. `ChangeDetector` decides
    /// which of them are new.
    public static func events(
        tickets: [Ticket],
        issues: [LinearIssue],
        slackMessages: [SlackRoutineMessage]?,
        now: Date
    ) -> [QueueEvent] {
        var events: [QueueEvent] = []
        let ticketsByID = Dictionary(tickets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ticketsByIdentifier = Dictionary(
            tickets.map { ($0.identifier.uppercased(), $0) }, uniquingKeysWith: { first, _ in first }
        )

        for ticket in tickets {
            events.append(QueueEvent(
                key: "ticket:\(ticket.id)", kind: .newTicket, source: .linear,
                ticketID: ticket.id, ticketIdentifier: ticket.identifier,
                ticketTitle: ticket.title, ticketURL: ticket.url
            ))
            if let commentID = ticket.questionCommentID {
                events.append(QueueEvent(
                    key: "linear:\(commentID):question", kind: .question, source: .linear,
                    ticketID: ticket.id, ticketIdentifier: ticket.identifier,
                    ticketTitle: ticket.title, ticketURL: ticket.url, detail: ticket.questionForKyle
                ))
            }
            if ticket.isStale {
                // Re-keyed whenever human activity moves, so a ticket can go
                // stale again after someone touches it.
                let since = Int((ticket.lastHumanActivityAt ?? ticket.createdAt).timeIntervalSince1970)
                events.append(QueueEvent(
                    key: "stale:\(ticket.id):\(since)", kind: .stale, source: .linear,
                    ticketID: ticket.id, ticketIdentifier: ticket.identifier,
                    ticketTitle: ticket.title, ticketURL: ticket.url
                ))
            }
        }

        for issue in issues {
            guard let ticket = ticketsByID[issue.id] else { continue }
            for comment in issue.comments where MarkerParser.markers(in: comment.body).contains(.fixPR) {
                events.append(QueueEvent(
                    key: "linear:\(comment.id)", kind: .fixPR, source: .linear,
                    ticketID: ticket.id, ticketIdentifier: ticket.identifier,
                    ticketTitle: ticket.title, ticketURL: ticket.url,
                    prURL: MarkerParser.prURL(in: comment.body)
                ))
            }
        }

        for message in slackMessages ?? [] {
            let ticket = ticketsByIdentifier[message.ticketIdentifier.uppercased()]
            switch message.kind {
            case .fixProposal:
                // Fix Approvals ignores anything older than its window.
                guard !message.asProposal.isExpired(now: now) else { continue }
                events.append(QueueEvent(
                    key: "slack:\(message.ts)", kind: .fixProposal, source: .slack,
                    ticketID: ticket?.id, ticketIdentifier: message.ticketIdentifier,
                    ticketTitle: ticket?.title, ticketURL: ticket?.url,
                    slackChannel: message.channel, slackTS: message.ts, detail: message.rootCause
                ))
            case .prodDebug:
                events.append(QueueEvent(
                    key: "slack:\(message.ts)", kind: .prodDebug, source: .slack,
                    ticketID: ticket?.id, ticketIdentifier: message.ticketIdentifier,
                    ticketTitle: ticket?.title, ticketURL: ticket?.url,
                    slackChannel: message.channel, slackTS: message.ts, detail: message.rootCause
                ))
            }
        }
        return events
    }
}

/// What has already been notified, persisted across launches.
public struct SeenState: Codable, Hashable, Sendable {
    /// Event key → last time it was present in a successful poll.
    public var seen: [String: Date]
    /// Sources whose first successful poll has been absorbed silently.
    public var primedSources: Set<QueueEvent.Source>
    /// `yyyy-MM-dd` of the last stale digest.
    public var lastStaleDigestDay: String?

    public init(seen: [String: Date] = [:], primedSources: Set<QueueEvent.Source> = [], lastStaleDigestDay: String? = nil) {
        self.seen = seen
        self.primedSources = primedSources
        self.lastStaleDigestDay = lastStaleDigestDay
    }

    /// Keys absent from every poll for this long are forgotten.
    public static let retention: TimeInterval = 60 * 86_400
}

public enum ChangeDetector {
    /// Returns the events to notify and updates `state`.
    ///
    /// - Only sources in `succeededSources` are considered, so a failed Slack
    ///   poll neither notifies nor forgets anything.
    /// - The first successful poll of each source marks everything seen
    ///   without notifying.
    /// - Stale tickets are collapsed into at most one digest event a day.
    public static func process(
        events: [QueueEvent],
        state: inout SeenState,
        succeededSources: Set<QueueEvent.Source>,
        now: Date,
        calendar: Calendar = .current
    ) -> [QueueEvent] {
        var deliver: [QueueEvent] = []
        var newStale: [QueueEvent] = []
        var deliveredKeys = Set<String>()

        for source in [QueueEvent.Source.linear, .slack] where succeededSources.contains(source) {
            let sourceEvents = events.filter { $0.source == source }
            let primed = state.primedSources.contains(source)
            for event in sourceEvents {
                let isNew = state.seen[event.key] == nil
                if !primed || !isNew {
                    state.seen[event.key] = now
                } else if event.kind == .stale {
                    newStale.append(event)
                } else if deliveredKeys.insert(event.key).inserted {
                    deliver.append(event)
                    state.seen[event.key] = now
                }
            }
            state.primedSources.insert(source)
        }

        if !newStale.isEmpty {
            let today = dayString(now, calendar: calendar)
            if state.lastStaleDigestDay != today {
                deliver.append(QueueEvent(
                    key: "stale-digest:\(today)", kind: .stale, source: .linear,
                    ticketID: newStale.count == 1 ? newStale[0].ticketID : nil,
                    ticketIdentifier: newStale.count == 1 ? newStale[0].ticketIdentifier : nil,
                    ticketTitle: newStale.count == 1 ? newStale[0].ticketTitle : nil,
                    ticketURL: newStale.count == 1 ? newStale[0].ticketURL : nil,
                    count: newStale.count
                ))
                for event in newStale { state.seen[event.key] = now }
                state.lastStaleDigestDay = today
            }
            // Otherwise leave them unseen so tomorrow's digest picks them up.
        }

        state.seen = state.seen.filter { now.timeIntervalSince($0.value) < SeenState.retention }
        return deliver
    }

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
