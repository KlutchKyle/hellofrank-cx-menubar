import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HelloFrankCore

let referenceNow = Date(timeIntervalSince1970: 1_791_000_000)

func daysAgo(_ days: Double, from now: Date = referenceNow) -> Date {
    now.addingTimeInterval(-days * 86_400)
}

let kyle = LinearUser(id: "user-kyle", name: "Kyle Volner")
let diana = LinearUser(id: "user-diana", name: "Diana")
let supportBot = LinearUser(id: "user-support", name: "Customer Support")

func comment(
    _ id: String,
    _ body: String,
    daysAgo days: Double,
    by user: LinearUser? = kyle
) -> LinearComment {
    LinearComment(id: id, body: body, createdAt: daysAgo(days), user: user)
}

func issue(
    _ identifier: String,
    createdDaysAgo: Double = 30,
    stateName: String = "Todo",
    stateType: String = "unstarted",
    labels: [String] = [],
    comments: [LinearComment] = [],
    history: [LinearHistoryEntry] = []
) -> LinearIssue {
    LinearIssue(
        id: "id-\(identifier)",
        identifier: identifier,
        title: "Title of \(identifier)",
        url: URL(string: "https://linear.app/hellofrank/issue/\(identifier)/title")!,
        createdAt: daysAgo(createdDaysAgo),
        updatedAt: daysAgo(1),
        state: LinearState(name: stateName, type: stateType),
        labels: labels,
        comments: comments,
        history: history
    )
}

func proposal(
    _ identifier: String,
    reactions: Set<String> = [],
    postedDaysAgo: Double = 1,
    ts: String? = nil
) -> FixProposal {
    let postedAt = daysAgo(postedDaysAgo)
    return FixProposal(
        ticketIdentifier: identifier,
        channel: "D123",
        ts: ts ?? String(format: "%.6f", postedAt.timeIntervalSince1970),
        postedAt: postedAt,
        reactions: reactions
    )
}

func slackMessage(
    _ kind: SlackRoutineMessage.Kind,
    _ identifier: String,
    reactions: Set<String> = [],
    postedDaysAgo: Double = 1,
    text: String? = nil
) -> SlackRoutineMessage {
    let postedAt = daysAgo(postedDaysAgo)
    let header = kind == .fixProposal ? "fix-proposal" : "prod-debug"
    return SlackRoutineMessage(
        kind: kind,
        ticketIdentifier: identifier,
        channel: "D123",
        ts: String(format: "%.6f", postedAt.timeIntervalSince1970),
        postedAt: postedAt,
        text: text ?? "[\(header) \(identifier)] Something\n*Root cause:* the cron job\n*Fix:* retry it",
        reactions: reactions
    )
}

let config = QueueConfig()

func resolve(_ issue: LinearIssue, proposal: FixProposal? = nil, viewerID: String? = kyle.id) -> PipelineResolver.Resolution {
    PipelineResolver.resolve(issue: issue, proposal: proposal, viewerID: viewerID, config: config)
}

/// Replays canned responses, in order, and records requests.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let reply = next(recording: request) else { throw APIError.network(code: -1) }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers
        )!
        return (Data(reply.body.utf8), response)
    }

    private func next(recording request: URLRequest) -> Reply? {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return replies.isEmpty ? nil : replies.removeFirst()
    }

    func bodyString(_ index: Int) -> String {
        requests[index].httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
