import XCTest
@testable import ChatPulseCore

final class RingLogTests: XCTestCase {
    func testCapacityDropsOldestEntries() {
        let log = RingLog(capacity: 2)
        log.append(LogEntry(level: .info, message: "one"))
        log.append(LogEntry(level: .info, message: "two"))
        log.append(LogEntry(level: .info, message: "three"))

        XCTAssertEqual(log.snapshot().map(\.message), ["two", "three"])
    }
}
