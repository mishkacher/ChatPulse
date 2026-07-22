import XCTest
@testable import ChatPulseCore

final class RingLogTests: XCTestCase {
    func testCapacityDropsOldestEntries() {
        let log = RingLog(capacity: 2)
        log.append(LogEntry(level: .info, message: "один"))
        log.append(LogEntry(level: .info, message: "два"))
        log.append(LogEntry(level: .info, message: "три"))

        XCTAssertEqual(log.snapshot().map(\.message), ["два", "три"])
    }
}
