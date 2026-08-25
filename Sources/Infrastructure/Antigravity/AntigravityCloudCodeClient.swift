import Foundation
import Domain

/// Google Cloud Code endpoints Antigravity uses for quota, reachable with the user's own OAuth
/// access token even when the desktop app is closed.
///
/// Expired access tokens are refreshed with Antigravity's public OAuth client. Refreshed tokens
/// stay in memory and are never written back to Antigravity's Keychain item.
///
/// Reverse-engineered from the Antigravity app; endpoints may change without notice.
struct AntigravityCloudCodeClient: Sendable {

    enum Outcome: Sendable {
        case ok(Data)
        /// HTTP 401 — the access token was rejected and should be refreshed once.
        case authFailed
        /// Transport error or any other non-2xx (403 license failure, 404, 5xx, …).
        case unavailable
    }

    enum RefreshOutcome: Sendable {
        case refreshed(accessToken: String, expiresAt: Date)
        case failed
    }

    static let baseURLs = [
        "https://daily-cloudcode-pa.googleapis.com",
        "https://cloudcode-pa.googleapis.com"
    ]
    static let quotaSummaryPath = "/v1internal:retrieveUserQuotaSummary"
    static let fetchModelsPath = "/v1internal:fetchAvailableModels"
    static let loadCodeAssistPath = "/v1internal:loadCodeAssist"
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    static let clientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    static let clientSecret = "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"

    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    init(networkClient: any NetworkClient, timeout: TimeInterval = 15.0) {
        self.networkClient = networkClient
        self.timeout = timeout
    }

    /// POSTs a JSON body to `path` on each base URL in turn.
    func post(path: String, token: String, body: [String: String] = [:]) async -> Outcome {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)

        for base in Self.baseURLs {
            guard let url = URL(string: base + path) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("antigravity", forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await networkClient.request(request),
                  let http = response as? HTTPURLResponse else {
                AppLog.network.debug("Antigravity: \(base)\(path) unreachable")
                continue
            }

            if http.statusCode == 401 {
                AppLog.network.debug("Antigravity: \(path) rejected token (HTTP \(http.statusCode))")
                return .authFailed
            }
            if http.statusCode == 403 {
                AppLog.network.debug("Antigravity: \(path) unavailable for this account (HTTP 403)")
                return .unavailable
            }
            if (200..<300).contains(http.statusCode) {
                return .ok(data)
            }
            AppLog.network.debug("Antigravity: \(base)\(path) returned HTTP \(http.statusCode)")
        }
        return .unavailable
    }

    /// Exchanges the stored refresh token for a short-lived access token.
    func refreshAccessToken(refreshToken: String, now: Date) async -> RefreshOutcome {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "client_secret", value: Self.clientSecret)
        ]

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await networkClient.request(request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let payload = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !payload.accessToken.isEmpty,
              payload.expiresIn > 0 else {
            AppLog.network.error("Antigravity: OAuth token refresh failed")
            return .failed
        }

        return .refreshed(
            accessToken: payload.accessToken,
            expiresAt: now.addingTimeInterval(payload.expiresIn)
        )
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}
