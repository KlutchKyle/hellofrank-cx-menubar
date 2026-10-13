import XCTest
@testable import HelloFrankCore

final class ChangeDetectorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func event(_ key: String, _ kind: QueueEvent.Kind, _ source: QueueEvent.Source = .linear) -> QueueEvent {
        QueueEvent(key: key, kind: kind, source: source, ticketIdentifier: "HEL-1")
    }

    private func run(_ events: [QueueEvent], _ state: inout SeenState, sources: Set<QueueEvent.Source> = [.linear, .slack], now: Date = referenceNow) -> [String] {
        ChangeDetector.process(events: events, state: &state, succeededSources: sources, now: now, calendar: calendar).map(\.key)
    }

    func testFirstLaunchMarksEverythingSeenWithoutNotifying() {
        var state = SeenState()
        let events = [event("ticket:1", .newTicket), event("slack:1.0", .fixProposal, .slack)]
        XCTAssertEqual(run(events, &state), [])
        XCTAssertEqual(state.primedSources, [.linear, .slack])
        XCTAssertEqual(run(events, &state), [])
    }

    func testNotifiesOnlyNewKeysOnce() {
        var state = SeenState()
        _ = run([event("ticket:1", .newTicket)], &state)
        XCTAssertEqual(run([event("ticket:1", .newTicket), event("ticket:2", .newTicket)], &state), ["ticket:2"])
        XCTAssertEqual(run([event("ticket:1", .newTicket), event("ticket:2", .newTicket)], &state), [])
    }

    func testNeverReplaysAfterRelaunch() throws {
        var state = SeenState()
        _ = run([event("ticket:1", .newTicket)], &state)
        _ = run([event("ticket:1", .newTicket), event("linear:c9", .fixPR)], &state)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/state.json")
        let file = StateFile(url: url)
        try file.save(PersistedState(seen: state))
        var reloaded = try XCTUnwrap(file.load()).seen
        XCTAssertEqual(run([event("ticket:1", .newTicket), event("linear:c9", .fixPR)], &reloaded), [])
    }

    func testFailedSourceNeitherNotifiesNorPrimes() {
        var state = SeenState()
        let slackEvent = event("slack:1.0", .fixProposal, .slack)
        XCTAssertEqual(run([event("ticket:1", .newTicket), slackEvent], &state, sources: [.linear]), [])
        XCTAssertEqual(state.primedSources, [.linear])
        // Slack connects later: its backlog is absorbed silently.
        XCTAssertEqual(run([slackEvent], &state, sources: [.linear, .slack]), [])
        XCTAssertEqual(run([slackEvent, event("slack:2.0", .fixProposal, .slack)], &state), ["slack:2.0"])
    }

    func testStaleIsBatchedOncePerDay() {
        var state = SeenState()
        _ = run([], &state)
        let morning = referenceNow
        XCTAssertEqual(run([event("stale:1:0", .stale), event("stale:2:0", .stale)], &state, now: morning).count, 1)
        let digest = ChangeDetector.process(
            events: [event("stale:1:0", .stale), event("stale:2:0", .stale), event("stale:3:0", .stale)],
            state: &state, succeededSources: [.linear], now: morning.addingTimeInterval(3600), calendar: calendar
        )
        XCTAssertTrue(digest.isEmpty, "second digest on the same day")
        let nextDay = ChangeDetector.process(
            events: [event("stale:1:0", .stale), event("stale:2:0", .stale), event("stale:3:0", .stale)],
            state: &state, succeededSources: [.linear], now: morning.addingTimeInterval(86_400), calendar: calendar
        )
        XCTAssertEqual(nextDay.count, 1)
        XCTAssertEqual(nextDay.first?.kind, .stale)
        XCTAssertEqual(nextDay.first?.count, 1)
    }

    func testDigestCountsTickets() {
        var state = SeenState()
        _ = run([], &state)
        let delivered = ChangeDetector.process(
            events: [event("stale:1:0", .stale), event("stale:2:0", .stale), event("stale:3:0", .stale)],
            state: &state, succeededSources: [.linear], now: referenceNow, calendar: calendar
        )
        XCTAssertEqual(delivered.map(\.count), [3])
    }

    func testForgetsKeysAbsentForRetentionPeriod() {
        var state = SeenState()
        _ = run([event("ticket:1", .newTicket)], &state)
        _ = run([], &state, now: referenceNow.addingTimeInterval(SeenState.retention + 1))
        XCTAssertNil(state.seen["ticket:1"])
    }

    func testPlannerEmitsExpectedKeys() {
        let issues = [
            issue("HEL-1", comments: [
                comment("q1", "<!-- cx-triage -->\nQuestion for Kyle: ok?", daysAgo: 1),
                comment("pr1", "<!-- fix-pr --> https://github.com/a/b/pull/3", daysAgo: 1),
            ]),
            issue("HEL-2", createdDaysAgo: 40),
        ]
        let slack = [
            slackMessage(.fixProposal, "HEL-2"),
            slackMessage(.fixProposal, "HEL-2", postedDaysAgo: 10),
            slackMessage(.prodDebug, "HEL-9"),
        ]
        let tickets = QueueBuilder.build(issues: issues, slackMessages: slack, viewerID: kyle.id, config: config, now: referenceNow)
        let events = QueueEventPlanner.events(tickets: tickets, issues: issues, slackMessages: slack, now: referenceNow)
        let byKind = Dictionary(grouping: events, by: \.kind).mapValues { $0.count }
        XCTAssertEqual(byKind[.newTicket], 2)
        XCTAssertEqual(byKind[.question], 1)
        XCTAssertEqual(byKind[.fixPR], 1)
        XCTAssertEqual(byKind[.fixProposal], 1, "expired proposal skipped")
        XCTAssertEqual(byKind[.prodDebug], 1)
        XCTAssertEqual(byKind[.stale], 2)
        let pr = events.first { $0.kind == .fixPR }
        XCTAssertEqual(pr?.prURL?.absoluteString, "https://github.com/a/b/pull/3")
        XCTAssertEqual(pr?.key, "linear:pr1")
    }
}
