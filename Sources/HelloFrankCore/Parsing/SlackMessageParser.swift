import Foundation

public enum SlackMessageParser {
    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^\s*\[(fix-proposal|prod-debug)\s+(HEL-\d+)\b[^\]]*\]"#,
        options: [.caseInsensitive]
    )

    /// Recognises `[fix-proposal HEL-1234]` and `[prod-debug HEL-1234]` on the
    /// first line of a message.
    public static func header(of text: String) -> (kind: SlackRoutineMessage.Kind, identifier: String)? {
        let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let range = NSRange(firstLine.startIndex..., in: firstLine)
        guard let match = headerRegex.firstMatch(in: firstLine, range: range),
              let kindRange = Range(match.range(at: 1), in: firstLine),
              let idRange = Range(match.range(at: 2), in: firstLine) else { return nil }
        let kind: SlackRoutineMessage.Kind =
            firstLine[kindRange].lowercased() == "fix-proposal" ? .fixProposal : .prodDebug
        return (kind, firstLine[idRange].uppercased())
    }

    /// The value of a `Label: value` line, ignoring Slack emphasis and bullets,
    /// e.g. `*Root cause:* the cron job…` → `the cron job…`.
    public static func field(_ label: String, in text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        guard let regex = try? NSRegularExpression(
            pattern: #"^[\s*_•>-]*"# + escaped + #"[\s*_]*:[\s*_]*(.+?)[\s*_]*$"#,
            options: [.caseInsensitive, .anchorsMatchLines]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[valueRange].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Slack message timestamps ("1712345678.123456") as dates.
    public static func date(fromTS ts: String) -> Date? {
        Double(ts).map(Date.init(timeIntervalSince1970:))
    }
}
