import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Kyle's identity in Slack, from `auth.test`.
public struct SlackIdentity: Codable, Hashable, Sendable {
    public var userID: String
    public var user: String
    public var team: String?

    public init(userID: String, user: String, team: String?) {
        self.userID = userID
        self.user = user
        self.team = team
    }
}

/// Slack Web API client using Kyle's user token. It only reads the self-DM
/// and adds reactions; it never posts messages.
public struct SlackClient: Sendable {
    public static let baseURL = URL(string: "https://slack.com/api/")!

    /// Fix Approvals looks back 7 days; reading a little further lets the app
    /// show proposals that have just expired instead of silently dropping them.
    public static let defaultLookback: TimeInterval = 14 * 86_400

    private let token: String
    private let transport: any HTTPTransport

    public init(token: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.token = token
        self.transport = transport
    }

    // MARK: Calls

    public func authTest() async throws -> SlackIdentity {
        let response: AuthTestResponse = try await call("auth.test", [:])
        guard let userID = response.user_id else { throw APIError.decoding(service: "Slack") }
        return SlackIdentity(userID: userID, user: response.user ?? userID, team: response.team)
    }

    /// The self-DM channel the routines post into.
    public func openSelfDM(userID: String) async throws -> String {
        let response: OpenResponse = try await call("conversations.open", ["users": userID])
        guard let id = response.channel?.id else { throw APIError.decoding(service: "Slack") }
        return id
    }

    public func history(channel: String, oldest: Date) async throws -> [SlackMessage] {
        var messages: [SlackMessage] = []
        var cursor: String?
        var pages = 0
        repeat {
            var params = [
                "channel": channel,
                "oldest": String(format: "%.6f", oldest.timeIntervalSince1970),
                "limit": "200",
            ]
            if let cursor { params["cursor"] = cursor }
            let response: HistoryResponse = try await call("conversations.history", params)
            messages += response.messages ?? []
            let next = response.response_metadata?.next_cursor ?? ""
            cursor = (response.has_more ?? false) && !next.isEmpty ? next : nil
            pages += 1
        } while cursor != nil && pages < 10
        return messages
    }

    public func replies(channel: String, ts: String) async throws -> [SlackMessage] {
        let response: HistoryResponse = try await call(
            "conversations.replies", ["channel": channel, "ts": ts, "limit": "200"]
        )
        // The first message is the parent.
        return (response.messages ?? []).filter { $0.ts != ts }
    }

    /// Adds a reaction as Kyle. `already_reacted` counts as success.
    public func addReaction(_ name: String, channel: String, ts: String) async throws {
        do {
            let _: BasicResponse = try await call(
                "reactions.add", ["name": name, "channel": channel, "timestamp": ts]
            )
        } catch APIError.slack(code: "already_reacted") {
            return
        }
    }

    /// `[fix-proposal …]` and `[prod-debug …]` messages in the self-DM.
    public func fetchRoutineMessages(channel: String, now: Date, lookback: TimeInterval = defaultLookback) async throws -> [SlackRoutineMessage] {
        let raw = try await history(channel: channel, oldest: now.addingTimeInterval(-lookback))
        var result: [SlackRoutineMessage] = []
        for message in raw {
            guard let ts = message.ts,
                  let text = message.text,
                  let header = SlackMessageParser.header(of: text),
                  let postedAt = SlackMessageParser.date(fromTS: ts) else { continue }
            var latestReplyAt = message.latest_reply.flatMap(SlackMessageParser.date(fromTS:))
            let replyCount = message.reply_count ?? 0
            // `latest_reply` normally comes with the parent; only fall back to
            // conversations.replies for proposals still waiting on Kyle.
            if latestReplyAt == nil, replyCount > 0, header.kind == .fixProposal,
               Set(message.reactionNames).isDisjoint(with: SlackReaction.all) {
                let replies = try await replies(channel: channel, ts: ts)
                latestReplyAt = replies.compactMap { $0.ts.flatMap(SlackMessageParser.date(fromTS:)) }.max()
            }
            result.append(SlackRoutineMessage(
                kind: header.kind,
                ticketIdentifier: header.identifier,
                channel: channel,
                ts: ts,
                postedAt: postedAt,
                text: text,
                reactions: Set(message.reactionNames),
                replyCount: replyCount,
                latestReplyAt: latestReplyAt
            ))
        }
        return result
    }

    // MARK: Transport

    private func call<T: SlackResponse>(_ method: String, _ params: [String: String]) async throws -> T {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(method), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, http) = try await transport.send(request)
        if http.statusCode == 429 {
            throw APIError.rateLimited(service: "Slack", retryAfter: Int(http.value(forHTTPHeaderField: "Retry-After") ?? ""))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(service: "Slack", status: http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw APIError.decoding(service: "Slack")
        }
        guard decoded.ok else { throw APIError.slack(code: decoded.error ?? "unknown_error") }
        return decoded
    }

    static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.sorted { $0.key < $1.key }.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

// MARK: - Wire format

protocol SlackResponse: Decodable {
    var ok: Bool { get }
    var error: String? { get }
}

public struct SlackMessage: Decodable, Sendable {
    public struct Reaction: Decodable, Sendable {
        public var name: String
        public var users: [String]?
        public var count: Int?
    }

    public var ts: String?
    public var text: String?
    public var user: String?
    public var reactions: [Reaction]?
    public var reply_count: Int?
    public var latest_reply: String?
    public var thread_ts: String?

    /// Reaction names without skin-tone suffixes.
    public var reactionNames: [String] {
        (reactions ?? []).map { reaction in
            reaction.name.components(separatedBy: "::").first ?? reaction.name
        }
    }
}

struct BasicResponse: SlackResponse {
    var ok: Bool
    var error: String?
}

struct AuthTestResponse: SlackResponse {
    var ok: Bool
    var error: String?
    var user_id: String?
    var user: String?
    var team: String?
}

struct OpenResponse: SlackResponse {
    struct Channel: Decodable { var id: String }
    var ok: Bool
    var error: String?
    var channel: Channel?
}

struct HistoryResponse: SlackResponse {
    struct Metadata: Decodable { var next_cursor: String? }
    var ok: Bool
    var error: String?
    var messages: [SlackMessage]?
    var has_more: Bool?
    var response_metadata: Metadata?
}
