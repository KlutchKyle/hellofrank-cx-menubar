import Foundation

/// HTML-comment markers the routines and Toni write into Linear comments.
public enum Marker: String, CaseIterable, Codable, Sendable {
    case cxTriage = "cx-triage"
    case fixDebug = "fix-debug"
    case fixProposal = "fix-proposal"
    case fixPR = "fix-pr"
    case fixDeclined = "fix-declined"
    case toniNudge = "toni-nudge"
    case toniBot = "toni-bot"
}

public enum MarkerParser {
    // Matches `<!-- name -->` and tolerates extra text after the name,
    // e.g. `<!-- fix-proposal HEL-1234 -->`.
    private static let markerRegex = try! NSRegularExpression(
        pattern: #"<!--\s*([A-Za-z][A-Za-z0-9-]*)[^>]*?-->"#
    )
    private static let githubPRRegex = try! NSRegularExpression(
        pattern: #"https://github\.com/[^\s/]+/[^\s/]+/pull/\d+"#
    )
    private static let anyURLRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>()\[\]"'`]+"#
    )

    public static func markers(in body: String) -> Set<Marker> {
        let range = NSRange(body.startIndex..., in: body)
        var found = Set<Marker>()
        for match in markerRegex.matches(in: body, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: body) else { continue }
            if let marker = Marker(rawValue: body[nameRange].lowercased()) {
                found.insert(marker)
            }
        }
        return found
    }

    /// The PR link in a `fix-pr` comment: a GitHub pull URL if present,
    /// otherwise the first URL in the body.
    public static func prURL(in body: String) -> URL? {
        firstMatch(githubPRRegex, in: body).flatMap(URL.init(string:))
            ?? firstMatch(anyURLRegex, in: body)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:")) }
                .flatMap(URL.init(string:))
    }

    public static let questionPrefix = "Question for Kyle:"

    /// The text after "Question for Kyle:", up to the end of that paragraph.
    /// Tolerates Markdown emphasis around the prefix (`**Question for Kyle:**`).
    public static func questionForKyle(in body: String) -> String? {
        let withoutComments = body.replacingOccurrences(
            of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression
        )
        guard let prefixRange = withoutComments.range(of: questionPrefix, options: .caseInsensitive) else {
            return nil
        }
        var rest = withoutComments[prefixRange.upperBound...]
        if let paragraphEnd = rest.range(of: "\n\n") {
            rest = rest[..<paragraphEnd.lowerBound]
        }
        let question = rest
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_ \t"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return question.isEmpty ? "" : question
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
