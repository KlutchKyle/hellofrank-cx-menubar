import Foundation

/// API failures. Descriptions carry HTTP status and API error codes only,
/// never request headers or tokens.
public enum APIError: Error, Equatable, LocalizedError, Sendable {
    case missingCredentials(service: String)
    case network(code: Int)
    case http(service: String, status: Int)
    case rateLimited(service: String, retryAfter: Int?)
    case linear(codes: [String])
    case slack(code: String)
    case decoding(service: String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials(let service):
            return "\(service): no credentials saved"
        case .network(let code):
            return "Network error (\(code))"
        case .http(let service, let status):
            return "\(service): HTTP \(status)"
        case .rateLimited(let service, let retryAfter):
            return "\(service): rate limited" + (retryAfter.map { ", retry in \($0)s" } ?? "")
        case .linear(let codes):
            return "Linear: " + (codes.isEmpty ? "API error" : codes.joined(separator: ", "))
        case .slack(let code):
            return "Slack: \(code)"
        case .decoding(let service):
            return "\(service): unexpected response"
        }
    }

    /// Whether credentials are the likely cause (shown as a hint in Settings).
    public var isAuthFailure: Bool {
        switch self {
        case .http(_, let status): return status == 401 || status == 403
        case .slack(let code): return ["invalid_auth", "not_authed", "token_revoked", "token_expired", "account_inactive", "missing_scope"].contains(code)
        case .linear(let codes): return codes.contains { $0.uppercased().contains("AUTH") }
        case .missingCredentials: return true
        default: return false
        }
    }
}
