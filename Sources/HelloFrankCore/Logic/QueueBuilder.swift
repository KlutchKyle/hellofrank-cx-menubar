import Foundation

public enum QueueBuilder {
    /// Turns raw Linear issues and Slack messages into the sorted queue.
    ///
    /// - Parameter slackMessages: nil when Slack isn't connected.
    public static func build(
        issues: [LinearIssue],
        slackMessages: [SlackRoutineMessage]?,
        viewerID: String?,
        config: QueueConfig,
        now: Date
    ) -> [Ticket] {
        let proposals = latestProposals(slackMessages ?? [])
        let tickets = openIssues(issues).map { issue -> Ticket in
            let proposal = proposals[issue.identifier.uppercased()]
            let resolution = PipelineResolver.resolve(
                issue: issue, proposal: proposal, viewerID: viewerID, config: config
            )
            return Ticket(
                id: issue.id,
                identifier: issue.identifier,
                title: issue.title,
                url: issue.url,
                createdAt: issue.createdAt,
                stateName: issue.state.name,
                labels: issue.labels,
                pipelineState: resolution.state,
                lastHumanActivityAt: resolution.lastHumanActivityAt,
                isStale: PipelineResolver.isStale(
                    createdAt: issue.createdAt,
                    lastHumanActivityAt: resolution.lastHumanActivityAt,
                    now: now,
                    config: config
                ),
                questionForKyle: resolution.questionForKyle,
                questionCommentID: resolution.questionCommentID,
                prURL: resolution.prURL,
                proposal: proposal
            )
        }
        return sorted(tickets)
    }

    /// Drops completed, canceled and Duplicate tickets. The API filter already
    /// excludes the first two; Duplicate may not be typed as canceled.
    public static func openIssues(_ issues: [LinearIssue]) -> [LinearIssue] {
        issues.filter { issue in
            let type = issue.state.type.lowercased()
            return type != "completed" && type != "canceled"
                && issue.state.name.caseInsensitiveCompare("Duplicate") != .orderedSame
        }
    }

    /// Oldest first by `createdAt`; never depends on API order.
    public static func sorted(_ tickets: [Ticket]) -> [Ticket] {
        tickets.sorted { lhs, rhs in
            lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.identifier < rhs.identifier
        }
    }

    /// Newest `[fix-proposal]` message per ticket identifier.
    public static func latestProposals(_ messages: [SlackRoutineMessage]) -> [String: FixProposal] {
        var result: [String: FixProposal] = [:]
        for message in messages where message.kind == .fixProposal {
            let key = message.ticketIdentifier.uppercased()
            if let existing = result[key], existing.postedAt >= message.postedAt { continue }
            result[key] = message.asProposal
        }
        return result
    }

    /// Proposals waiting on ✅ or ❌, then questions, each oldest first.
    public static func needsYou(_ tickets: [Ticket], now: Date) -> [Ticket] {
        let waiting = tickets.filter { $0.needsKyle(now: now) }
        return sorted(waiting.filter { $0.pipelineState == .waitingOnYou })
            + sorted(waiting.filter { $0.pipelineState == .question })
    }

    public static func badgeCount(_ tickets: [Ticket], now: Date) -> Int {
        tickets.filter { $0.needsKyle(now: now) }.count
    }

    /// Search by identifier or title, optionally CX-labelled tickets only.
    public static func filter(_ tickets: [Ticket], search: String, cxOnly: Bool) -> [Ticket] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return tickets.filter { ticket in
            if cxOnly && !ticket.isCX { return false }
            guard !query.isEmpty else { return true }
            return ticket.identifier.localizedCaseInsensitiveContains(query)
                || ticket.title.localizedCaseInsensitiveContains(query)
        }
    }
}
