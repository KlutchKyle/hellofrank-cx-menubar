import Foundation

/// Non-secret settings that shape the queue.
public struct QueueConfig: Codable, Hashable, Sendable {
    public var projectSlug: String
    public var assigneeEmail: String
    public var staleThresholdDays: Int
    /// Comment authors that are never human activity.
    public var botAuthors: Set<String>

    public static let defaultProjectSlug = "565216a9d74a"
    public static let defaultAssigneeEmail = "kyle@hellofrank.ai"
    public static let defaultStaleThresholdDays = 14
    public static let defaultBotAuthors: Set<String> = ["Customer Support", "GitHub Copilot", "Linear"]

    public init(
        projectSlug: String = defaultProjectSlug,
        assigneeEmail: String = defaultAssigneeEmail,
        staleThresholdDays: Int = defaultStaleThresholdDays,
        botAuthors: Set<String> = defaultBotAuthors
    ) {
        self.projectSlug = projectSlug
        self.assigneeEmail = assigneeEmail
        self.staleThresholdDays = staleThresholdDays
        self.botAuthors = botAuthors
    }

    public var staleThreshold: TimeInterval { TimeInterval(staleThresholdDays) * 86_400 }
}
