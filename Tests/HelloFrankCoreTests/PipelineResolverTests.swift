import XCTest
@testable import HelloFrankCore

final class PipelineResolverTests: XCTestCase {
    // MARK: Individual states

    func testUntouched() {
        XCTAssertEqual(resolve(issue("HEL-1")).state, .untouched)
        let humanOnly = issue("HEL-1", comments: [comment("c1", "Customer says it's broken", daysAgo: 2, by: diana)])
        XCTAssertEqual(resolve(humanOnly).state, .untouched)
    }

    func testTriaged() {
        let ticket = issue("HEL-1", comments: [comment("c1", "<!-- cx-triage -->\nLooks like a sync bug.", daysAgo: 5)])
        XCTAssertEqual(resolve(ticket).state, .triaged)
    }

    func testDebuggedLikeHEL4171() {
        let ticket = issue("HEL-4171", comments: [
            comment("c1", "<!-- cx-triage -->\nTriage notes", daysAgo: 10),
            comment("c2", "<!-- fix-debug -->\nRoot cause found", daysAgo: 4),
        ])
        XCTAssertEqual(resolve(ticket).state, .debugged)
    }

    func testProposedWhenSlackMessageMissing() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- fix-debug -->", daysAgo: 4),
            comment("c2", "<!-- fix-proposal -->", daysAgo: 3),
        ])
        XCTAssertEqual(resolve(ticket).state, .proposed)
    }

    func testWaitingOnYou() {
        let ticket = issue("HEL-1", comments: [comment("c2", "<!-- fix-proposal -->", daysAgo: 1)])
        XCTAssertEqual(resolve(ticket, proposal: proposal("HEL-1")).state, .waitingOnYou)
    }

    func testConflictingReactionsStayWaitingOnYou() {
        let p = proposal("HEL-1", reactions: [SlackReaction.approve, SlackReaction.decline])
        XCTAssertTrue(p.isConflicting)
        XCTAssertEqual(resolve(issue("HEL-1"), proposal: p).state, .waitingOnYou)
    }

    func testApprovedAndDeclinePending() {
        XCTAssertEqual(resolve(issue("HEL-1"), proposal: proposal("HEL-1", reactions: [SlackReaction.approve])).state, .approvedPending)
        XCTAssertEqual(resolve(issue("HEL-1"), proposal: proposal("HEL-1", reactions: [SlackReaction.decline])).state, .declinePending)
    }

    func testImplementing() {
        let p = proposal("HEL-1", reactions: [SlackReaction.approve, SlackReaction.implementing])
        XCTAssertEqual(resolve(issue("HEL-1"), proposal: p).state, .implementing)
    }

    func testPROpenTakesURLFromComment() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- fix-pr -->\nhttps://github.com/hf/app/pull/42", daysAgo: 1),
        ])
        let resolution = resolve(ticket, proposal: proposal("HEL-1", reactions: [SlackReaction.approve, SlackReaction.implementing]))
        XCTAssertEqual(resolution.state, .prOpen)
        XCTAssertEqual(resolution.prURL?.absoluteString, "https://github.com/hf/app/pull/42")
    }

    func testDeclinedByCommentNewerThanProposal() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- fix-proposal -->", daysAgo: 3),
            comment("c2", "<!-- fix-declined -->", daysAgo: 2),
        ])
        XCTAssertEqual(resolve(ticket).state, .declined)
    }

    func testOlderDeclineDoesNotHideNewerProposal() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- fix-proposal -->", daysAgo: 6),
            comment("c2", "<!-- fix-declined -->", daysAgo: 5),
            comment("c3", "<!-- fix-proposal -->", daysAgo: 1),
        ])
        XCTAssertEqual(resolve(ticket).state, .proposed)
        XCTAssertEqual(resolve(ticket, proposal: proposal("HEL-1")).state, .waitingOnYou)
    }

    func testDeclinedBySlackRecord() {
        let p = proposal("HEL-1", reactions: [SlackReaction.decline, SlackReaction.declined])
        XCTAssertEqual(resolve(issue("HEL-1"), proposal: p).state, .declined)
    }

    func testQuestionForKyle() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- cx-triage -->\nQuestion for Kyle: refund them?", daysAgo: 2),
        ])
        let resolution = resolve(ticket)
        XCTAssertEqual(resolution.state, .question)
        XCTAssertEqual(resolution.questionForKyle, "refund them?")
        XCTAssertEqual(resolution.questionCommentID, "c1")
    }

    func testQuestionAnsweredByKyle() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- cx-triage -->\nQuestion for Kyle: refund them?", daysAgo: 2),
            comment("c2", "Yes, refund.", daysAgo: 1, by: kyle),
        ])
        XCTAssertEqual(resolve(ticket).state, .triaged)
    }

    func testQuestionNotAnsweredBySomeoneElseOrARoutine() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- cx-triage -->\nQuestion for Kyle: refund them?", daysAgo: 3),
            comment("c2", "Any update?", daysAgo: 2, by: diana),
            comment("c3", "<!-- toni-nudge -->\nPing", daysAgo: 1, by: kyle),
        ])
        XCTAssertEqual(resolve(ticket).state, .question)
        // Without knowing Kyle's ID, any human reply counts.
        XCTAssertEqual(resolve(ticket, viewerID: nil).state, .triaged)
    }

    func testOnlyLatestTriageCommentAsks() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- cx-triage -->\nQuestion for Kyle: old?", daysAgo: 5),
            comment("c2", "<!-- cx-triage -->\nRe-triaged, no questions.", daysAgo: 1),
        ])
        XCTAssertEqual(resolve(ticket).state, .triaged)
    }

    // MARK: Precedence

    func testPrecedenceOrder() {
        let all = issue("HEL-1", comments: [
            comment("c1", "<!-- cx-triage -->\nQuestion for Kyle: ok?", daysAgo: 6),
            comment("c2", "<!-- fix-debug -->", daysAgo: 5),
            comment("c3", "<!-- fix-proposal -->", daysAgo: 4),
            comment("c4", "<!-- fix-declined -->", daysAgo: 3),
        ])
        // Pending Slack proposal beats Declined and Question.
        XCTAssertEqual(resolve(all, proposal: proposal("HEL-1")).state, .waitingOnYou)
        // Without the proposal, Declined beats Question.
        XCTAssertEqual(resolve(all).state, .declined)

        var withPR = all
        withPR.comments.append(comment("c5", "<!-- fix-pr --> https://github.com/a/b/pull/1", daysAgo: 1))
        XCTAssertEqual(resolve(withPR, proposal: proposal("HEL-1")).state, .prOpen)

        let questionAndDebug = issue("HEL-1", comments: [
            comment("c1", "<!-- cx-triage -->\nQuestion for Kyle: ok?", daysAgo: 6),
            comment("c2", "<!-- fix-debug -->", daysAgo: 5),
        ])
        XCTAssertEqual(resolve(questionAndDebug).state, .question)
    }

    func testCommentOrderDoesNotDependOnAPIOrder() {
        let ticket = issue("HEL-1", comments: [
            comment("c2", "<!-- fix-declined -->", daysAgo: 2),
            comment("c1", "<!-- fix-proposal -->", daysAgo: 3),
        ])
        XCTAssertEqual(resolve(ticket).state, .declined)
    }

    // MARK: Human activity

    func testHumanActivityIgnoresMarkersAndBots() {
        let ticket = issue("HEL-1", comments: [
            comment("c1", "<!-- cx-triage --> by routine", daysAgo: 1),
            comment("c2", "Auto reply", daysAgo: 1, by: supportBot),
            comment("c3", "Copilot says hi", daysAgo: 1, by: LinearUser(name: "GitHub Copilot")),
            comment("c4", "Linear bot", daysAgo: 1, by: LinearUser(name: "Linear")),
            comment("c5", "Integration", daysAgo: 1, by: nil),
            comment("c6", "<!-- toni-bot --> nudge", daysAgo: 1),
            comment("c7", "Real human", daysAgo: 9, by: diana),
        ])
        XCTAssertEqual(resolve(ticket).lastHumanActivityAt, daysAgo(9))
    }

    func testStatusChangeCountsAsHumanActivity() {
        let ticket = issue("HEL-1", history: [
            LinearHistoryEntry(createdAt: daysAgo(3), fromState: "Todo", toState: "In Progress", actor: kyle),
            LinearHistoryEntry(createdAt: daysAgo(1), fromState: "In Progress", toState: "In Review", actor: nil),
            LinearHistoryEntry(createdAt: daysAgo(0.5), fromState: nil, toState: nil, actor: diana),
        ])
        XCTAssertEqual(resolve(ticket).lastHumanActivityAt, daysAgo(3))
    }

    func testStale() {
        XCTAssertTrue(PipelineResolver.isStale(createdAt: daysAgo(30), lastHumanActivityAt: daysAgo(14), now: referenceNow, config: config))
        XCTAssertFalse(PipelineResolver.isStale(createdAt: daysAgo(30), lastHumanActivityAt: daysAgo(13.9), now: referenceNow, config: config))
        XCTAssertTrue(PipelineResolver.isStale(createdAt: daysAgo(20), lastHumanActivityAt: nil, now: referenceNow, config: config))
        XCTAssertFalse(PipelineResolver.isStale(createdAt: daysAgo(3), lastHumanActivityAt: nil, now: referenceNow, config: config))
    }
}
