import Foundation

/// Slack reaction names the routines and Fix Approvals use.
public enum SlackReaction {
    public static let approve = "white_check_mark"
    public static let decline = "x"
    public static let implementing = "rocket"
    public static let declined = "no_entry_sign"

    public static let all: Set<String> = [approve, decline, implementing, declined]
}

/// Kyle's answer to a fix proposal.
public enum ProposalDecision: String, Codable, Hashable, Sendable {
    case approve
    case decline

    public var reactionName: String {
        switch self {
        case .approve: return SlackReaction.approve
        case .decline: return SlackReaction.decline
        }
    }
}

/// A `[fix-proposal HEL-…]` message in Kyle's self-DM, plus its reactions.
public struct FixProposal: Codable, Hashable, Sendable {
    public var ticketIdentifier: String
    public var channel: String
    public var ts: String
    public var postedAt: Date
    public var reactions: Set<String>
    /// Time of the newest thread reply (Fix Approvals reminders, PR links).
    public var latestReminderAt: Date?
    public var rootCause: String?
    public var fix: String?

    public init(
        ticketIdentifier: String,
        channel: String,
        ts: String,
        postedAt: Date,
        reactions: Set<String>,
        latestReminderAt: Date? = nil,
        rootCause: String? = nil,
        fix: String? = nil
    ) {
        self.ticketIdentifier = ticketIdentifier
        self.channel = channel
        self.ts = ts
        self.postedAt = postedAt
        self.reactions = reactions
        self.latestReminderAt = latestReminderAt
        self.rootCause = rootCause
        self.fix = fix
    }

    /// Fix Approvals only looks back this far.
    public static let approvalWindow: TimeInterval = 7 * 24 * 60 * 60

    public var hasApprove: Bool { reactions.contains(SlackReaction.approve) }
    public var hasDecline: Bool { reactions.contains(SlackReaction.decline) }
    public var hasImplementing: Bool { reactions.contains(SlackReaction.implementing) }
    public var hasDeclinedRecord: Bool { reactions.contains(SlackReaction.declined) }

    /// None of ✅ ❌ 🚀 🚫: waiting on Kyle.
    public var isAwaitingDecision: Bool { reactions.isDisjoint(with: SlackReaction.all) }

    /// ✅ and ❌ both present and Fix Approvals hasn't resolved it; it skips these.
    public var isConflicting: Bool {
        hasApprove && hasDecline && !hasImplementing && !hasDeclinedRecord
    }

    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(postedAt) > Self.approvalWindow
    }
}
