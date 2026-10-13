import Foundation

/// Where a ticket sits in the triage → debug → fix pipeline.
///
/// `PipelineResolver` assigns exactly one of these per ticket. The order of the
/// cases mirrors the precedence table in the build spec, with two extra
/// transitional states (`approvedPending`, `declinePending`) for the window
/// between Kyle reacting in Slack and Fix Approvals picking it up, and
/// `proposed` for a `fix-proposal` comment whose Slack message is out of reach.
public enum PipelineState: String, Codable, Hashable, Sendable, CaseIterable {
    case prOpen
    case implementing
    case waitingOnYou
    case approvedPending
    case declinePending
    case declined
    case question
    case proposed
    case debugged
    case triaged
    case untouched

    /// Label shown in the row's state pill.
    public var title: String {
        switch self {
        case .prOpen: return "PR open"
        case .implementing: return "Implementing"
        case .waitingOnYou: return "Waiting on you"
        case .approvedPending: return "Approved"
        case .declinePending: return "Declining"
        case .declined: return "Declined"
        case .question: return "Question"
        case .proposed: return "Proposed"
        case .debugged: return "Debugged"
        case .triaged: return "Triaged"
        case .untouched: return "Untouched"
        }
    }

    /// Whether the state is waiting on Kyle. Expired proposals are excluded
    /// separately in `Ticket.needsKyle`.
    public var needsKyle: Bool {
        self == .waitingOnYou || self == .question
    }
}
