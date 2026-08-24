import Foundation

/// A Claude Code profile exposed as its own provider card.
public struct ClaudeExtraAccount: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let configDir: String

    public init(id: String, label: String, configDir: String) {
        self.id = id
        self.label = label
        self.configDir = configDir
    }

    public var configDirectoryURL: URL {
        URL(
            fileURLWithPath: (configDir as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }
}
