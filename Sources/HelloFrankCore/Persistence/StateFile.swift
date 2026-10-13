import Foundation

/// Everything the app keeps between launches: notification dedupe state and
/// the last good queue for instant display. Never holds secrets.
public struct PersistedState: Codable, Sendable {
    public var seen: SeenState
    public var cachedTickets: [Ticket]
    public var cachedAt: Date?

    public init(seen: SeenState = SeenState(), cachedTickets: [Ticket] = [], cachedAt: Date? = nil) {
        self.seen = seen
        self.cachedTickets = cachedTickets
        self.cachedAt = cachedAt
    }
}

/// A small JSON file in Application Support.
public struct StateFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/ai.hellofrank.cx-menubar/state.json`
    public static func standard(fileManager: FileManager = .default) -> StateFile {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return StateFile(url: base.appendingPathComponent("ai.hellofrank.cx-menubar/state.json"))
    }

    public func load() -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedState.self, from: data)
    }

    public func save(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
