import Foundation
import Testing
@testable import Infrastructure

@Suite("Claude Extra Account Settings Tests")
struct ClaudeExtraAccountTests {
    @Test
    func `decodes extra accounts from JSON settings store`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-extra-accounts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settingsURL = directory.appendingPathComponent("settings.json")
        let json = """
        {
          "claude": {
            "extraAccounts": [
              {
                "id": "claude-devops",
                "label": "Claude · ccd",
                "configDir": "~/.claude-devops"
              },
              {
                "id": "claude-creative",
                "label": "Claude · ccc",
                "configDir": "/tmp/.claude-creative"
              }
            ]
          }
        }
        """
        try json.write(to: settingsURL, atomically: true, encoding: .utf8)
        let store = JSONSettingsStore(fileURL: settingsURL)

        let accounts: [ClaudeExtraAccount]? = store.readDecodable(key: "claude.extraAccounts")

        #expect(accounts == [
            ClaudeExtraAccount(
                id: "claude-devops",
                label: "Claude · ccd",
                configDir: "~/.claude-devops"
            ),
            ClaudeExtraAccount(
                id: "claude-creative",
                label: "Claude · ccc",
                configDir: "/tmp/.claude-creative"
            ),
        ])
    }

    @Test
    func `missing extra accounts decodes as nil`() {
        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-settings-\(UUID().uuidString).json")
        let store = JSONSettingsStore(fileURL: settingsURL)

        let accounts: [ClaudeExtraAccount]? = store.readDecodable(key: "claude.extraAccounts")

        #expect(accounts == nil)
    }
}
