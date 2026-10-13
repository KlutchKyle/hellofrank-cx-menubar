import Foundation

/// One open ticket as the app shows it.
public struct Ticket: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var identifier: String
    public var title: String
    public var url: URL
    public var createdAt: Date
    public var stateName: String
    public var labels: [String]
    public var pipelineState: PipelineState
    public var lastHumanActivityAt: Date?
    public var isStale: Bool
    public var questionForKyle: String?
    /// The `cx-triage` comment that asked `questionForKyle`.
    public var questionCommentID: String?
    public var prURL: URL?
    public var proposal: FixProposal?

    public init(
        id: String,
        identifier: String,
        title: String,
        url: URL,
        createdAt: Date,
        stateName: String,
        labels: [String],
        pipelineState: PipelineState,
        lastHumanActivityAt: Date?,
        isStale: Bool,
        questionForKyle: String? = nil,
        questionCommentID: String? = nil,
        prURL: URL? = nil,
        proposal: FixProposal? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.stateName = stateName
        self.labels = labels
        self.pipelineState = pipelineState
        self.lastHumanActivityAt = lastHumanActivityAt
        self.isStale = isStale
        self.questionForKyle = questionForKyle
        self.questionCommentID = questionCommentID
        self.prURL = prURL
        self.proposal = proposal
    }

    /// Labels shown as chips and used by the "CX only" filter.
    public static let cxLabels: Set<String> = ["cx", "affecting customers"]

    public var cxLabelNames: [String] {
        labels.filter { Self.cxLabels.contains($0.lowercased()) }
    }

    public var isCX: Bool { !cxLabelNames.isEmpty }

    /// Whole days since the ticket was created.
    public func ageDays(now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(createdAt) / 86_400))
    }

    /// Counts toward the menu bar badge and the "Needs you" section.
    public func needsKyle(now: Date) -> Bool {
        switch pipelineState {
        case .question:
            return true
        case .waitingOnYou:
            return !(proposal?.isExpired(now: now) ?? false)
        default:
            return false
        }
    }
}
