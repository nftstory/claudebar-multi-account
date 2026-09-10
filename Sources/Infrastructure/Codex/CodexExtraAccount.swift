import Foundation

/// A Codex CLI home (`CODEX_HOME`) exposed as its own provider card.
public struct CodexExtraAccount: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let codexHome: String

    public init(id: String, label: String, codexHome: String) {
        self.id = id
        self.label = label
        self.codexHome = codexHome
    }

    public var codexHomeURL: URL {
        URL(
            fileURLWithPath: (codexHome as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }
}
