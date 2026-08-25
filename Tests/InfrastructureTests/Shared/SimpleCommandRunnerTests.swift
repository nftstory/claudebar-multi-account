import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

@Suite
struct SimpleCommandRunnerTests {
    @Test
    func `captures stdout from a completed command`() throws {
        let result = try SimpleCommandRunner().run("/bin/echo", ["hello"], timeout: 1)

        #expect(result == CLIResult(output: "hello\n", exitCode: 0))
    }

    @Test
    func `returns a nonzero exit code without throwing`() throws {
        let result = try SimpleCommandRunner().run("/bin/sh", ["-c", "exit 7"], timeout: 1)

        #expect(result.exitCode == 7)
        #expect(result.output.isEmpty)
    }

    @Test
    func `terminates a command at the hard timeout`() {
        #expect(throws: ProbeError.timeout) {
            try SimpleCommandRunner().run("/bin/sleep", ["5"], timeout: 0.05)
        }
    }
}
