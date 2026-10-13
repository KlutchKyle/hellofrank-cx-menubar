import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only Linear GraphQL client. The app never writes to Linear.
public struct LinearClient: Sendable {
    public static let endpoint = URL(string: "https://api.linear.app/graphql")!

    private let apiKey: String
    private let transport: any HTTPTransport

    public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    // MARK: Queries

    static let viewerQuery = "query Viewer { viewer { id name email } }"

    static func queueQuery(pageSize: Int) -> String {
        """
        query Queue($after: String, $slug: String!, $email: String!) {
          issues(
            first: \(pageSize)
            after: $after
            filter: {
              project: { slugId: { eq: $slug } }
              assignee: { email: { eq: $email } }
              state: { type: { nin: ["completed", "canceled"] } }
            }
          ) {
            nodes {
              id identifier title url createdAt updatedAt
              state { name type }
              labels(first: 20) { nodes { name } }
              comments(first: 50) {
                nodes { id body createdAt user { id name } }
              }
              history(first: 25) {
                nodes { createdAt fromState { name } toState { name } actor { id name } }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
        """
    }

    /// Default page size from the spec; halved if Linear rejects the query as too complex.
    public static let defaultPageSize = 50

    // MARK: Public API

    /// Used by Settings → Test connection.
    public func viewer() async throws -> LinearViewer {
        let response: GraphQLResponse<ViewerData> = try await post(query: Self.viewerQuery, variables: [:])
        guard let viewer = response.data?.viewer else { throw APIError.decoding(service: "Linear") }
        return viewer
    }

    /// All open issues in the project assigned to `assigneeEmail`, every page.
    public func fetchQueue(projectSlug: String, assigneeEmail: String) async throws -> [LinearIssue] {
        var pageSize = Self.defaultPageSize
        while true {
            do {
                return try await fetchQueue(projectSlug: projectSlug, assigneeEmail: assigneeEmail, pageSize: pageSize)
            } catch is QueryTooComplex {
                guard pageSize > 10 else { throw APIError.linear(codes: ["QUERY_TOO_COMPLEX"]) }
                pageSize /= 2
            }
        }
    }

    private struct QueryTooComplex: Error {}

    private func fetchQueue(projectSlug: String, assigneeEmail: String, pageSize: Int) async throws -> [LinearIssue] {
        var issues: [LinearIssue] = []
        var cursor: String?
        var pages = 0
        repeat {
            var variables: [String: String] = ["slug": projectSlug, "email": assigneeEmail]
            if let cursor { variables["after"] = cursor }
            let response: GraphQLResponse<QueueData> = try await post(
                query: Self.queueQuery(pageSize: pageSize), variables: variables
            )
            guard let connection = response.data?.issues else { throw APIError.decoding(service: "Linear") }
            issues += connection.nodes.map(\.issue)
            cursor = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
            pages += 1
        } while cursor != nil && pages < 40
        return issues
    }

    private func post<T: Decodable>(query: String, variables: [String: String]) async throws -> GraphQLResponse<T> {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        // Personal API keys take no "Bearer" prefix.
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, http) = try await transport.send(request)
        if http.statusCode == 429 {
            throw APIError.rateLimited(service: "Linear", retryAfter: Int(http.value(forHTTPHeaderField: "Retry-After") ?? ""))
        }
        let decoded = try? JSONCoding.decoder().decode(GraphQLResponse<T>.self, from: data)
        if let errors = decoded?.errors, !errors.isEmpty {
            if errors.contains(where: { ($0.message ?? "").lowercased().contains("complex") }) {
                throw QueryTooComplex()
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw APIError.http(service: "Linear", status: http.statusCode)
            }
            throw APIError.linear(codes: errors.map(\.code))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(service: "Linear", status: http.statusCode)
        }
        guard let decoded else { throw APIError.decoding(service: "Linear") }
        return decoded
    }
}

// MARK: - Wire format

struct GraphQLResponse<T: Decodable>: Decodable {
    var data: T?
    var errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    var message: String?
    var extensions: Extensions?

    struct Extensions: Decodable {
        var code: String?
        var type: String?
    }

    var code: String {
        extensions?.code ?? extensions?.type ?? "GRAPHQL_ERROR"
    }
}

struct ViewerData: Decodable {
    var viewer: LinearViewer
}

struct QueueData: Decodable {
    var issues: Connection<IssueNode>
}

struct Connection<Node: Decodable>: Decodable {
    var nodes: [Node]
    var pageInfo: PageInfo
}

struct Nodes<Node: Decodable>: Decodable {
    var nodes: [Node]
}

struct PageInfo: Decodable {
    var hasNextPage: Bool
    var endCursor: String?
}

struct IssueNode: Decodable {
    struct Named: Decodable { var name: String }
    struct CommentNode: Decodable {
        var id: String
        var body: String
        var createdAt: Date
        var user: LinearUser?
    }
    struct HistoryNode: Decodable {
        var createdAt: Date
        var fromState: Named?
        var toState: Named?
        var actor: LinearUser?
    }

    var id: String
    var identifier: String
    var title: String
    var url: URL
    var createdAt: Date
    var updatedAt: Date
    var state: LinearState
    var labels: Nodes<Named>?
    var comments: Nodes<CommentNode>?
    var history: Nodes<HistoryNode>?

    var issue: LinearIssue {
        LinearIssue(
            id: id,
            identifier: identifier,
            title: title,
            url: url,
            createdAt: createdAt,
            updatedAt: updatedAt,
            state: state,
            labels: labels?.nodes.map(\.name) ?? [],
            comments: comments?.nodes.map {
                LinearComment(id: $0.id, body: $0.body, createdAt: $0.createdAt, user: $0.user)
            } ?? [],
            history: history?.nodes.map {
                LinearHistoryEntry(
                    createdAt: $0.createdAt, fromState: $0.fromState?.name,
                    toState: $0.toState?.name, actor: $0.actor
                )
            } ?? []
        )
    }
}
