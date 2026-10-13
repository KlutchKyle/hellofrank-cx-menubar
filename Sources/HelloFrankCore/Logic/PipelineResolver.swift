import Foundation

/// Derives a ticket's pipeline state from its Linear comment markers and its
/// Slack proposal. All routine comments post under Kyle's name, so markers,
/// not authors, decide what is AI and what is human.
public enum PipelineResolver {
    public struct Resolution: Hashable, Sendable {
        public var state: PipelineState
        public var prURL: URL?
        public var questionForKyle: String?
        public var questionCommentID: String?
        public var lastHumanActivityAt: Date?
    }

    /// - Parameters:
    ///   - proposal: the newest Slack `[fix-proposal]` message for this ticket, if any.
    ///   - viewerID: Kyle's Linear user ID. When known, only his own human
    ///     comments count as answering a question; otherwise any human comment does.
    public static func resolve(
        issue: LinearIssue,
        proposal: FixProposal?,
        viewerID: String?,
        config: QueueConfig
    ) -> Resolution {
        let comments = issue.comments.sorted { $0.createdAt < $1.createdAt }
        let marked = comments.map { (comment: $0, markers: MarkerParser.markers(in: $0.body)) }

        func latest(_ marker: Marker) -> LinearComment? {
            marked.last { $0.markers.contains(marker) }?.comment
        }

        let lastHuman = lastHumanActivity(issue: issue, config: config)
        var resolution = Resolution(state: .untouched, lastHumanActivityAt: lastHuman)

        let fixPR = latest(.fixPR)
        let triage = latest(.cxTriage)
        let proposalComment = latest(.fixProposal)
        let declinedComment = latest(.fixDeclined)

        // Question details are kept even when another state wins, so the row
        // can still show them; only `.question` counts toward the badge.
        if let triage, let question = MarkerParser.questionForKyle(in: triage.body) {
            let answered = comments.contains { comment in
                comment.createdAt > triage.createdAt
                    && isHuman(comment, config: config)
                    && (viewerID == nil || comment.user?.id == viewerID)
            }
            if !answered {
                resolution.questionForKyle = question
                resolution.questionCommentID = triage.id
            }
        }

        if let fixPR {
            resolution.state = .prOpen
            resolution.prURL = MarkerParser.prURL(in: fixPR.body)
            return resolution
        }

        if let proposal {
            if proposal.hasImplementing {
                resolution.state = .implementing
                return resolution
            }
            if proposal.isAwaitingDecision || proposal.isConflicting {
                resolution.state = .waitingOnYou
                return resolution
            }
            if !proposal.hasDeclinedRecord {
                resolution.state = proposal.hasApprove ? .approvedPending : .declinePending
                return resolution
            }
        }

        let declinedByComment: Bool = {
            guard let declinedComment else { return false }
            guard let proposalComment else { return true }
            return declinedComment.createdAt > proposalComment.createdAt
        }()
        if declinedByComment || (proposal?.hasDeclinedRecord ?? false) {
            resolution.state = .declined
            return resolution
        }

        if resolution.questionForKyle != nil {
            resolution.state = .question
            return resolution
        }

        if proposalComment != nil {
            // A proposal was posted, but its Slack message is outside the
            // lookback window or Slack isn't connected.
            resolution.state = .proposed
            return resolution
        }

        if latest(.fixDebug) != nil {
            resolution.state = .debugged
        } else if triage != nil {
            resolution.state = .triaged
        }
        return resolution
    }

    /// A comment with none of the known markers, written by a person who is
    /// not one of the known bot accounts.
    public static func isHuman(_ comment: LinearComment, config: QueueConfig) -> Bool {
        guard let user = comment.user, !config.botAuthors.contains(user.name) else { return false }
        return MarkerParser.markers(in: comment.body).isEmpty
    }

    /// Newest human comment or status change made by a person.
    public static func lastHumanActivity(issue: LinearIssue, config: QueueConfig) -> Date? {
        let commentDates = issue.comments.filter { isHuman($0, config: config) }.map(\.createdAt)
        let statusDates = issue.history.filter { entry in
            guard entry.isStatusChange, let actor = entry.actor else { return false }
            return !config.botAuthors.contains(actor.name)
        }.map(\.createdAt)
        return (commentDates + statusDates).max()
    }

    /// Stale when nothing human has happened for the threshold; a ticket with
    /// no human activity at all is measured from its creation.
    public static func isStale(createdAt: Date, lastHumanActivityAt: Date?, now: Date, config: QueueConfig) -> Bool {
        now.timeIntervalSince(lastHumanActivityAt ?? createdAt) >= config.staleThreshold
    }
}
