import Foundation
import Testing
@testable import Infrastructure

@Suite("Codex Extra Account Settings Tests")
struct CodexExtraAccountTests {
    @Test
    func `decodes extra accounts from JSON settings store`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-codex-extra-accounts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settingsURL = directory.appendingPathComponent("settings.json")
        let json = """
        {
          "codex": {
            "extraAccounts": [
              {
                "id": "codex-creative",
                "label": "Codex · cc",
                "codexHome": "~/.codex-creative"
              }
            ]
          }
        }
        """
        try json.write(to: settingsURL, atomically: true, encoding: .utf8)
        let store = JSONSettingsStore(fileURL: settingsURL)

        let accounts: [CodexExtraAccount]? = store.readDecodable(key: "codex.extraAccounts")

        #expect(accounts == [
            CodexExtraAccount(id: "codex-creative", label: "Codex · cc", codexHome: "~/.codex-creative"),
        ])
        #expect(accounts?.first?.codexHomeURL.path.hasSuffix("/.codex-creative") == true)
    }

    @Test
    func `missing extra accounts decodes as nil`() {
        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-codex-settings-\(UUID().uuidString).json")
        let store = JSONSettingsStore(fileURL: settingsURL)

        let accounts: [CodexExtraAccount]? = store.readDecodable(key: "codex.extraAccounts")

        #expect(accounts == nil)
    }

    @Test
    func `snapshot carries the extra account provider id`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(
                usedPercent: 25,
                resetDescription: nil,
                windowDuration: 7 * 24 * 3600,
                resetsAt: Date().addingTimeInterval(3 * 24 * 3600)
            ),
            secondary: nil,
            planType: "pro"
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response, providerId: "codex-creative")

        #expect(snapshot.providerId == "codex-creative")
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "codex-creative" })
    }
}
