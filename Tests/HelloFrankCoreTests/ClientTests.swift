import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HelloFrankCore

final class LinearClientTests: XCTestCase {
    private func issueJSON(_ identifier: String, created: String) -> String {
        """
        {"id":"id-\(identifier)","identifier":"\(identifier)","title":"T \(identifier)",
         "url":"https://linear.app/hf/issue/\(identifier)/t","createdAt":"\(created)","updatedAt":"2026-10-01T00:00:00Z",
         "state":{"name":"Todo","type":"unstarted"},
         "labels":{"nodes":[{"name":"CX"}]},
         "comments":{"nodes":[{"id":"c1","body":"<!-- cx-triage -->","createdAt":"2026-09-01T10:00:00.123Z","user":{"id":"u1","name":"Kyle"}},
                              {"id":"c2","body":"from integration","createdAt":"2026-09-02T10:00:00Z","user":null}]},
         "history":{"nodes":[{"createdAt":"2026-09-03T00:00:00Z","fromState":{"name":"Todo"},"toState":{"name":"In Progress"},"actor":{"id":"u1","name":"Kyle"}}]}}
        """
    }

    func testPagesUntilDoneAndSendsKeyWithoutBearer() async throws {
        let page1 = #"{"data":{"issues":{"nodes":["# + issueJSON("HEL-2", created: "2026-09-01T00:00:00.000Z")
            + #"],"pageInfo":{"hasNextPage":true,"endCursor":"abc"}}}}"#
        let page2 = #"{"data":{"issues":{"nodes":["# + issueJSON("HEL-1", created: "2026-08-01T00:00:00Z")
            + #"],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
        let transport = MockTransport([.init(status: 200, body: page1), .init(status: 200, body: page2)])
        let client = LinearClient(apiKey: "lin_api_test", transport: transport)

        let issues = try await client.fetchQueue(projectSlug: "565216a9d74a", assigneeEmail: "kyle@hellofrank.ai")

        XCTAssertEqual(issues.map(\.identifier), ["HEL-2", "HEL-1"])
        XCTAssertEqual(issues[0].labels, ["CX"])
        XCTAssertEqual(issues[0].comments.count, 2)
        XCTAssertNil(issues[0].comments[1].user)
        XCTAssertEqual(issues[0].history.first?.toState, "In Progress")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "lin_api_test")
        XCTAssertTrue(transport.bodyString(0).contains("565216a9d74a"))
        XCTAssertTrue(transport.bodyString(1).contains("\"after\":\"abc\""))
    }

    func testHalvesPageSizeWhenTooComplex() async throws {
        let tooComplex = #"{"errors":[{"message":"Query too complex","extensions":{"code":"INVALID_INPUT"}}]}"#
        let ok = #"{"data":{"issues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#
        let transport = MockTransport([.init(status: 400, body: tooComplex), .init(status: 200, body: ok)])
        let issues = try await LinearClient(apiKey: "k", transport: transport)
            .fetchQueue(projectSlug: "s", assigneeEmail: "e")
        XCTAssertEqual(issues, [])
        XCTAssertTrue(transport.bodyString(0).contains("first: 50"))
        XCTAssertTrue(transport.bodyString(1).contains("first: 25"))
    }

    func testAuthErrorReportsStatusOnly() async {
        let body = #"{"errors":[{"message":"Authentication required","extensions":{"code":"AUTHENTICATION_ERROR"}}]}"#
        let transport = MockTransport([.init(status: 401, body: body)])
        do {
            _ = try await LinearClient(apiKey: "secret-key", transport: transport).viewer()
            XCTFail("expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(service: "Linear", status: 401))
            XCTAssertTrue(error.isAuthFailure)
            XCTAssertFalse(error.localizedDescription.contains("secret-key"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testViewer() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"data":{"viewer":{"id":"u1","name":"Kyle","email":"kyle@hellofrank.ai"}}}"#)])
        let viewer = try await LinearClient(apiKey: "k", transport: transport).viewer()
        XCTAssertEqual(viewer.email, "kyle@hellofrank.ai")
    }
}

final class SlackClientTests: XCTestCase {
    func testAlreadyReactedIsSuccess() async throws {
        let transport = MockTransport([.init(status: 200, body: #"{"ok":false,"error":"already_reacted"}"#)])
        try await SlackClient(token: "xoxp-1", transport: transport)
            .addReaction(SlackReaction.approve, channel: "D1", ts: "1.2")
        let body = transport.bodyString(0)
        XCTAssertTrue(body.contains("name=white_check_mark"))
        XCTAssertTrue(body.contains("timestamp=1.2"))
        XCTAssertTrue(body.contains("channel=D1"))
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer xoxp-1")
        XCTAssertEqual(transport.requests[0].url?.lastPathComponent, "reactions.add")
    }

    func testSlackErrorsSurfaceCodes() async {
        let transport = MockTransport([.init(status: 200, body: #"{"ok":false,"error":"invalid_auth"}"#)])
        do {
            try await SlackClient(token: "xoxp-1", transport: transport).addReaction("x", channel: "D1", ts: "1.2")
            XCTFail("expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .slack(code: "invalid_auth"))
            XCTAssertTrue(error.isAuthFailure)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testRateLimit() async {
        let transport = MockTransport([.init(status: 429, body: "", headers: ["Retry-After": "30"])])
        do {
            _ = try await SlackClient(token: "xoxp-1", transport: transport).authTest()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? APIError, .rateLimited(service: "Slack", retryAfter: 30))
        }
    }

    func testFetchRoutineMessages() async throws {
        let history = #"""
        {"ok":true,"has_more":true,"response_metadata":{"next_cursor":"next"},"messages":[
          {"ts":"1790900000.000100","text":"[fix-proposal HEL-1234] Login loop\n*Root cause:* cookie\n*Fix:* keep it",
           "reactions":[{"name":"eyes","count":1}],"reply_count":2},
          {"ts":"1790900001.000100","text":"Just chatting"}
        ]}
        """#
        let page2 = #"""
        {"ok":true,"has_more":false,"messages":[
          {"ts":"1790800000.000100","text":"[prod-debug HEL-77]\nRoot cause: disk full",
           "reactions":[{"name":"white_check_mark::skin-tone-2","count":1}],"reply_count":1,"latest_reply":"1790800500.000000"}
        ]}
        """#
        let replies = #"""
        {"ok":true,"messages":[
          {"ts":"1790900000.000100","text":"parent"},
          {"ts":"1790903600.000000","text":"Reminder: still waiting"}
        ]}
        """#
        let transport = MockTransport([
            .init(status: 200, body: history), .init(status: 200, body: page2), .init(status: 200, body: replies),
        ])
        let messages = try await SlackClient(token: "xoxp-1", transport: transport)
            .fetchRoutineMessages(channel: "D1", now: referenceNow)

        XCTAssertEqual(messages.count, 2)
        let proposal = try XCTUnwrap(messages.first { $0.kind == .fixProposal })
        XCTAssertEqual(proposal.ticketIdentifier, "HEL-1234")
        XCTAssertEqual(proposal.rootCause, "cookie")
        XCTAssertEqual(proposal.fix, "keep it")
        XCTAssertEqual(proposal.latestReplyAt?.timeIntervalSince1970 ?? 0, 1790903600, accuracy: 0.001)
        XCTAssertTrue(proposal.asProposal.isAwaitingDecision)

        let debug = try XCTUnwrap(messages.first { $0.kind == .prodDebug })
        XCTAssertEqual(debug.reactions, [SlackReaction.approve])
        XCTAssertEqual(debug.rootCause, "disk full")

        XCTAssertTrue(transport.bodyString(0).contains("oldest="))
        XCTAssertTrue(transport.bodyString(1).contains("cursor=next"))
        XCTAssertEqual(transport.requests[2].url?.lastPathComponent, "conversations.replies")
    }

    func testAuthAndOpenDM() async throws {
        let transport = MockTransport([
            .init(status: 200, body: #"{"ok":true,"user_id":"U1","user":"kyle","team":"hello, Frank"}"#),
            .init(status: 200, body: #"{"ok":true,"channel":{"id":"D42"}}"#),
        ])
        let client = SlackClient(token: "xoxp-1", transport: transport)
        let identity = try await client.authTest()
        XCTAssertEqual(identity, SlackIdentity(userID: "U1", user: "kyle", team: "hello, Frank"))
        let channel = try await client.openSelfDM(userID: identity.userID)
        XCTAssertEqual(channel, "D42")
        XCTAssertTrue(transport.bodyString(1).contains("users=U1"))
    }

    func testFormEncoding() {
        XCTAssertEqual(SlackClient.formEncode(["b": "a b&c", "a": "1.5"]), "a=1.5&b=a%20b%26c")
    }
}
