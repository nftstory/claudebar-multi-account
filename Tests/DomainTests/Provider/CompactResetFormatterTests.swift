import Foundation
import Testing
@testable import Domain

@Suite
struct CompactResetFormatterTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test
    func `formats a reset under one minute away`() {
        let resetDate = now.addingTimeInterval(42)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "<1m")
    }

    @Test
    func `formats a reset in minutes`() {
        let resetDate = now.addingTimeInterval(42 * 60)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "42m")
    }

    @Test
    func `formats a reset in hours and minutes`() {
        let resetDate = now.addingTimeInterval(2 * 60 * 60 + 8 * 60)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "2h 8m")
    }

    @Test
    func `formats a reset in one day and hours`() {
        let resetDate = now.addingTimeInterval(24 * 60 * 60 + 4 * 60 * 60)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "1d 4h")
    }

    @Test
    func `formats a reset in several days and hours`() {
        let resetDate = now.addingTimeInterval(6 * 24 * 60 * 60 + 23 * 60 * 60)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "6d 23h")
    }
}
