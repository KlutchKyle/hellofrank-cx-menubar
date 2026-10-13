import XCTest
@testable import HelloFrankCore

final class QueueBuilderTests: XCTestCase {
    private func build(_ issues: [LinearIssue], slack: [SlackRoutineMessage]? = nil) -> [Ticket] {
        QueueBuilder.build(issues: issues, slackMessages: slack, viewerID: kyle.id, config: config, now: referenceNow)
    }

    func testSortsOldestFirstRegardlessOfAPIOrder() {
        let tickets = build([
            issue("HEL-3", createdDaysAgo: 2),
            issue("HEL-1", createdDaysAgo: 40),
            issue("HEL-2", createdDaysAgo: 10),
        ])
        XCTAssertEqual(tickets.map(\.identifier), ["HEL-1", "HEL-2", "HEL-3"])
    }

    func testSortTieBreaksOnIdentifier() {
        let tickets = build([issue("HEL-9", createdDaysAgo: 5), issue("HEL-8", createdDaysAgo: 5)])
        XCTAssertEqual(tickets.map(\.identifier), ["HEL-8", "HEL-9"])
    }

    func testDropsDuplicateCompletedAndCanceled() {
        let tickets = build([
            issue("HEL-1", stateName: "Duplicate", stateType: "unstarted"),
            issue("HEL-2", stateName: "duplicate", stateType: "backlog"),
            issue("HEL-3", stateName: "Done", stateType: "completed"),
            issue("HEL-4", stateName: "Canceled", stateType: "canceled"),
            issue("HEL-5", stateName: "In Progress", stateType: "started"),
        ])
        XCTAssertEqual(tickets.map(\.identifier), ["HEL-5"])
    }

    func testAgeDays() {
        let ticket = build([issue("HEL-1", createdDaysAgo: 47.5)])[0]
        XCTAssertEqual(ticket.ageDays(now: referenceNow), 47)
    }

    func testAttachesNewestProposalPerTicket() {
        let old = slackMessage(.fixProposal, "HEL-1", reactions: [SlackReaction.decline, SlackReaction.declined], postedDaysAgo: 5)
        let new = slackMessage(.fixProposal, "HEL-1", postedDaysAgo: 1)
        let debug = slackMessage(.prodDebug, "HEL-1", postedDaysAgo: 0.5)
        let ticket = build([issue("HEL-1")], slack: [new, old, debug])[0]
        XCTAssertEqual(ticket.proposal?.ts, new.ts)
        XCTAssertEqual(ticket.pipelineState, .waitingOnYou)
        XCTAssertEqual(ticket.proposal?.rootCause, "the cron job")
        XCTAssertEqual(ticket.proposal?.fix, "retry it")
    }

    func testNeedsYouAndBadge() {
        let tickets = build([
            issue("HEL-1", createdDaysAgo: 50, comments: [comment("q", "<!-- cx-triage -->\nQuestion for Kyle: ?", daysAgo: 1)]),
            issue("HEL-2", createdDaysAgo: 40),
            issue("HEL-3", createdDaysAgo: 30),
            issue("HEL-4", createdDaysAgo: 20),
            issue("HEL-5", createdDaysAgo: 10),
        ], slack: [
            slackMessage(.fixProposal, "HEL-3"),
            slackMessage(.fixProposal, "HEL-2"),
            slackMessage(.fixProposal, "HEL-4", postedDaysAgo: 9),
            slackMessage(.fixProposal, "HEL-5", reactions: [SlackReaction.approve]),
        ])
        // Waiting proposals first (oldest ticket first), then questions; the
        // expired HEL-4 proposal and the approved HEL-5 don't count.
        XCTAssertEqual(QueueBuilder.needsYou(tickets, now: referenceNow).map(\.identifier), ["HEL-2", "HEL-3", "HEL-1"])
        XCTAssertEqual(QueueBuilder.badgeCount(tickets, now: referenceNow), 3)
        let expired = tickets.first { $0.identifier == "HEL-4" }!
        XCTAssertEqual(expired.pipelineState, .waitingOnYou)
        XCTAssertTrue(expired.proposal!.isExpired(now: referenceNow))
    }

    func testFilterBySearchAndCX() {
        let tickets = build([
            issue("HEL-1", labels: ["CX"]),
            issue("HEL-2", labels: ["Affecting Customers", "Bug"]),
            issue("HEL-3", labels: ["Bug"]),
        ])
        XCTAssertEqual(QueueBuilder.filter(tickets, search: "", cxOnly: true).map(\.identifier), ["HEL-1", "HEL-2"])
        XCTAssertEqual(QueueBuilder.filter(tickets, search: "hel-3", cxOnly: false).map(\.identifier), ["HEL-3"])
        XCTAssertEqual(QueueBuilder.filter(tickets, search: "title of hel-2", cxOnly: true).map(\.identifier), ["HEL-2"])
        XCTAssertEqual(tickets[1].cxLabelNames, ["Affecting Customers"])
    }

    func testStaleFlag() {
        let tickets = build([
            issue("HEL-1", createdDaysAgo: 30, comments: [comment("c", "hello", daysAgo: 15, by: diana)]),
            issue("HEL-2", createdDaysAgo: 30, comments: [comment("c", "hello", daysAgo: 2, by: diana)]),
        ])
        XCTAssertEqual(tickets.map(\.isStale), [true, false])
    }
}
