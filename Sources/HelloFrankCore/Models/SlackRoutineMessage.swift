import Foundation

/// A routine-authored message in Kyle's self-DM that the app understands.
public struct SlackRoutineMessage: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case fixProposal
        case prodDebug
    }

    public var kind: Kind
    public var ticketIdentifier: String
    public var channel: String
    public var ts: String
    public var postedAt: Date
    public var text: String
    public var reactions: Set<String>
    public var replyCount: Int
    public var latestReplyAt: Date?

    public init(
        kind: Kind,
        ticketIdentifier: String,
        channel: String,
        ts: String,
        postedAt: Date,
        text: String,
        reactions: Set<String>,
        replyCount: Int = 0,
        latestReplyAt: Date? = nil
    ) {
        self.kind = kind
        self.ticketIdentifier = ticketIdentifier
        self.channel = channel
        self.ts = ts
        self.postedAt = postedAt
        self.text = text
        self.reactions = reactions
        self.replyCount = replyCount
        self.latestReplyAt = latestReplyAt
    }

    public var rootCause: String? { SlackMessageParser.field("Root cause", in: text) }
    public var fix: String? { SlackMessageParser.field("Fix", in: text) }

    public var asProposal: FixProposal {
        FixProposal(
            ticketIdentifier: ticketIdentifier,
            channel: channel,
            ts: ts,
            postedAt: postedAt,
            reactions: reactions,
            latestReminderAt: latestReplyAt,
            rootCause: rootCause,
            fix: fix
        )
    }
}
