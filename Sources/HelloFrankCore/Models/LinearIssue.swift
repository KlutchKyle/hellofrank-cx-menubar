import Foundation

/// Raw Linear issue as returned by the queue query.
public struct LinearIssue: Codable, Hashable, Sendable {
    public var id: String
    public var identifier: String
    public var title: String
    public var url: URL
    public var createdAt: Date
    public var updatedAt: Date
    public var state: LinearState
    public var labels: [String]
    public var comments: [LinearComment]
    public var history: [LinearHistoryEntry]

    public init(
        id: String,
        identifier: String,
        title: String,
        url: URL,
        createdAt: Date,
        updatedAt: Date,
        state: LinearState,
        labels: [String] = [],
        comments: [LinearComment] = [],
        history: [LinearHistoryEntry] = []
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.labels = labels
        self.comments = comments
        self.history = history
    }
}

public struct LinearState: Codable, Hashable, Sendable {
    public var name: String
    public var type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

public struct LinearUser: Codable, Hashable, Sendable {
    public var id: String?
    public var name: String

    public init(id: String? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

public struct LinearComment: Codable, Hashable, Sendable {
    public var id: String
    public var body: String
    public var createdAt: Date
    /// Nil for integration and system comments.
    public var user: LinearUser?

    public init(id: String, body: String, createdAt: Date, user: LinearUser?) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.user = user
    }
}

/// One entry of an issue's history; only status changes matter here.
public struct LinearHistoryEntry: Codable, Hashable, Sendable {
    public var createdAt: Date
    public var fromState: String?
    public var toState: String?
    /// Nil when an automation or integration made the change.
    public var actor: LinearUser?

    public init(createdAt: Date, fromState: String?, toState: String?, actor: LinearUser?) {
        self.createdAt = createdAt
        self.fromState = fromState
        self.toState = toState
        self.actor = actor
    }

    public var isStatusChange: Bool {
        guard let toState else { return false }
        return toState != fromState
    }
}

public struct LinearViewer: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var email: String

    public init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}
