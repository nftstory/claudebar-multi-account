import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// Covers the "app closed" path (issue #201): no language server process, so the probe
/// falls back to the Keychain OAuth token + Google Cloud Code API.
@Suite
struct AntigravityCloudCodeFallbackTests {

    static let noProcessOutput = "12345 /path/to/some_other_binary --flag value"

    static let agyProcessOutput = """
    4242 /opt/homebrew/bin/agy --standalone --csrf_token agy-token-1 --app_data_dir antigravity
    """

    static func keychainBlob(access: String = "ya29.valid", refresh: String? = "1//refresh", expiry: String = "2030-01-01T00:00:00Z") -> String {
        var token: [String: Any] = ["access_token": access, "expiry": expiry]
        if let refresh { token["refresh_token"] = refresh }
        let json = try! JSONSerialization.data(withJSONObject: ["token": token])
        return "go-keyring-base64:" + json.base64EncodedString()
    }

    static let summaryJSON = """
    {"groups":[{"buckets":[
      {"bucketId":"gemini-5h","remainingFraction":0.9,"resetTime":"2025-01-01T05:00:00Z"},
      {"bucketId":"gemini-weekly","remainingFraction":0.7},
      {"bucketId":"3p-5h","remainingFraction":0.5},
      {"bucketId":"3p-weekly","remainingFraction":0.3}
    ]}]}
    """

    static let modelsJSON = """
    {"models":{
      "gemini-3-pro":{"displayName":"Gemini 3 Pro","quotaInfo":{"remainingFraction":0.65,"resetTime":"2026-09-01T00:00:00Z"}},
      "gemini-3-flash":{"displayName":"Gemini 3 Flash","quotaInfo":{"resetTime":"2026-09-02T00:00:00Z"}},
      "claude-sonnet":{"displayName":"Claude Sonnet","quotaInfo":{"remainingFraction":0.25}},
      "internal":{"displayName":"Hidden","isInternal":true,"quotaInfo":{"remainingFraction":1.0}},
      "no-quota":{"displayName":"No Quota"}
    }}
    """

    static let planJSON = """
    {"paidTier":{"name":"paid-tier"},"currentTier":{"name":"free-tier"}}
    """

    // MARK: - Helpers

    private func makeExecutor(process: String, keychain: CLIResult) -> MockCLIExecutor {
        let mock = MockCLIExecutor()
        given(mock)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { binary, _, _, _, _, _ in
                if binary.hasSuffix("security") { return keychain }
                return CLIResult(output: process, exitCode: 0)
            }
        return mock
    }

    private func http(_ status: Int, _ body: String, url: URL) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    // MARK: - agy CLI process

    @Test
    func `detects the agy CLI language server process`() {
        #expect(AntigravityUsageProbe.isAntigravityProcess(Self.agyProcessOutput))
    }

    @Test
    func `isAvailable returns true when only the agy process is running`() async {
        let executor = makeExecutor(process: Self.agyProcessOutput, keychain: CLIResult(output: "", exitCode: 44))
        let probe = AntigravityUsageProbe(cliExecutor: executor)

        #expect(await probe.isAvailable() == true)
    }

    // MARK: - Availability

    @Test
    func `isAvailable returns true when no process but keychain credentials exist`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let probe = AntigravityUsageProbe(cliExecutor: executor)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when no process and no keychain credentials`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: "not found", exitCode: 44))
        let probe = AntigravityUsageProbe(cliExecutor: executor)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Cloud Code quota summary

    @Test
    func `probe returns pooled quotas from Cloud Code when app is closed`() async throws {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        var authHeaders: [String] = []
        given(remote).request(.any).willProduce { request in
            authHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let url = request.url!
            if url.path.hasSuffix("retrieveUserQuotaSummary") {
                return self.http(200, Self.summaryJSON, url: url)
            }
            return self.http(404, "", url: url)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)
        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "antigravity")
        #expect(snapshot.quotas.count == 4)
        #expect(snapshot.quotas[0].quotaType == .session)
        #expect(snapshot.quotas[0].percentRemaining == 90.0)
        #expect(snapshot.quotas[3].quotaType == .modelSpecific("Claude Weekly"))
        #expect(snapshot.quotas[3].percentRemaining == 30.0)
        #expect(authHeaders.allSatisfy { $0 == "Bearer ya29.valid" })
    }

    @Test
    func `probe falls back to every model quota and current tier when summary returns 403`() async throws {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            let url = request.url!
            if url.path.hasSuffix("retrieveUserQuotaSummary") {
                return self.http(403, "no valid license", url: url)
            }
            if url.path.hasSuffix("fetchAvailableModels") {
                return self.http(200, Self.modelsJSON, url: url)
            }
            if url.path.hasSuffix("loadCodeAssist") {
                return self.http(200, Self.planJSON, url: url)
            }
            return self.http(404, "", url: url)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)
        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.count == 4)
        #expect(snapshot.quotas.contains { $0.quotaType == .modelSpecific("Gemini 3 Pro") && $0.percentRemaining == 65.0 })
        #expect(snapshot.quotas.contains { $0.quotaType == .modelSpecific("Claude Sonnet") && $0.percentRemaining == 25.0 })
        #expect(snapshot.quotas.contains { $0.quotaType == .modelSpecific("Gemini 3 Flash") && $0.percentRemaining == 0.0 })
        #expect(snapshot.quotas.contains { $0.quotaType == .modelSpecific("Hidden") && $0.percentRemaining == 100.0 })
        #expect(snapshot.quotas.first { $0.quotaType == .modelSpecific("Gemini 3 Pro") }?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z"))
        #expect(snapshot.quotas.allSatisfy { $0.resetText == nil })
        #expect(snapshot.accountTier == .custom("FREE-TIER"))
    }

    // MARK: - Token refresh

    @Test
    func `expired token is refreshed and cached in the probe instance`() async throws {
        let executor = makeExecutor(
            process: Self.noProcessOutput,
            keychain: CLIResult(output: Self.keychainBlob(access: "ya29.stale", expiry: "2020-01-01T00:00:00Z"), exitCode: 0)
        )
        let remote = MockNetworkClient()
        var refreshRequests = 0
        var quotaAuthHeaders: [String] = []
        given(remote).request(.any).willProduce { request in
            let url = request.url!
            if url == AntigravityCloudCodeClient.tokenURL {
                refreshRequests += 1
                let form = URLComponents(string: "?" + String(data: request.httpBody ?? Data(), encoding: .utf8)!)!
                let values = Dictionary(uniqueKeysWithValues: (form.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                #expect(values["grant_type"] == "refresh_token")
                #expect(values["refresh_token"] == "1//refresh")
                #expect(values["client_id"] == AntigravityCloudCodeClient.clientID)
                #expect(values["client_secret"] == AntigravityCloudCodeClient.clientSecret)
                return self.http(200, "{\"access_token\":\"ya29.refreshed\",\"expires_in\":3600}", url: url)
            }
            quotaAuthHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            if url.path.hasSuffix("retrieveUserQuotaSummary") {
                return self.http(200, Self.summaryJSON, url: url)
            }
            return self.http(404, "", url: url)
        }

        let probe = AntigravityUsageProbe(
            cliExecutor: executor,
            remoteNetworkClient: remote,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        _ = try await probe.probe()
        _ = try await probe.probe()

        #expect(refreshRequests == 1)
        #expect(quotaAuthHeaders.allSatisfy { $0 == "Bearer ya29.refreshed" })
    }

    @Test
    func `HTTP 401 refreshes once and retries with the new token`() async throws {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        var refreshRequests = 0
        given(remote).request(.any).willProduce { request in
            let url = request.url!
            if url == AntigravityCloudCodeClient.tokenURL {
                refreshRequests += 1
                return self.http(200, "{\"access_token\":\"ya29.after401\",\"expires_in\":3600}", url: url)
            }
            if url.path.hasSuffix("retrieveUserQuotaSummary") {
                let authorization = request.value(forHTTPHeaderField: "Authorization")
                return authorization == "Bearer ya29.valid"
                    ? self.http(401, "", url: url)
                    : self.http(200, Self.summaryJSON, url: url)
            }
            return self.http(404, "", url: url)
        }

        let snapshot = try await AntigravityUsageProbe(
            cliExecutor: executor,
            remoteNetworkClient: remote
        ).probe()

        #expect(snapshot.quotas.count == 4)
        #expect(refreshRequests == 1)
    }

    @Test
    func `detection executor failure falls through to Cloud Code`() async throws {
        let executor = MockCLIExecutor()
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { binary, _, _, _, _, _ in
                if binary.hasSuffix("pgrep") { throw ProbeError.timeout }
                if binary.hasSuffix("security") {
                    return CLIResult(output: Self.keychainBlob(), exitCode: 0)
                }
                return CLIResult(output: "", exitCode: 1)
            }
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            let url = request.url!
            if url.path.hasSuffix("retrieveUserQuotaSummary") {
                return self.http(200, Self.summaryJSON, url: url)
            }
            return self.http(404, "", url: url)
        }

        let snapshot = try await AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote).probe()

        #expect(snapshot.quotas.count == 4)
    }

    // MARK: - Errors

    @Test
    func `probe shows the sign-in instruction when no process and no credentials`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: "not found", exitCode: 44))
        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: MockNetworkClient())

        await #expect(throws: ProbeError.executionFailed("Open Antigravity once to sign in")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws sessionExpired with the Antigravity sign-in hint when refresh fails`() async {
        let executor = makeExecutor(
            process: Self.noProcessOutput,
            keychain: CLIResult(output: Self.keychainBlob(access: "ya29.stale", expiry: "2020-01-01T00:00:00Z"), exitCode: 0)
        )
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            self.http(400, "", url: request.url!)
        }
        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)

        do {
            _ = try await probe.probe()
            Issue.record("Expected sessionExpired")
        } catch let error as ProbeError {
            #expect(error.errorDescription == "Session expired. Open Antigravity to sign in again")
        } catch {
            Issue.record("Expected ProbeError, got \(error)")
        }
    }

    @Test
    func `probe throws sessionExpired when Cloud Code rejects the stored token`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            self.http(401, "", url: request.url!)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)

        await #expect(throws: ProbeError.sessionExpired(hint: "Open Antigravity to sign in again")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed when Cloud Code is unreachable`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            self.http(503, "", url: request.url!)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)

        await #expect(throws: ProbeError.executionFailed("Could not reach the Antigravity quota API")) {
            try await probe.probe()
        }
    }
}
