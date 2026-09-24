import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct ProcessRPCTransportTests {
    @Test
    func `consecutive receives return every line even when they arrive in one chunk`() async throws {
        // Both lines are written in a single write; the process then lingers so EOF cannot be what
        // delivers the second line.
        let transport = try ProcessRPCTransport(
            executable: "sh",
            arguments: ["-c", "printf 'first\\nsecond\\n'; sleep 3"]
        )
        defer { transport.close() }

        let first = try await transport.receive()
        let second = try await transport.receive()

        #expect(String(decoding: first, as: UTF8.self) == "first")
        #expect(String(decoding: second, as: UTF8.self) == "second")
    }

    @Test
    func `close ends a pending receive`() async throws {
        let transport = try ProcessRPCTransport(executable: "sh", arguments: ["-c", "sleep 30"])

        let reader = Task { try await transport.receive() }
        try await Task.sleep(nanoseconds: 200_000_000)
        transport.close()

        await #expect(throws: (any Error).self) { try await reader.value }
    }
}
