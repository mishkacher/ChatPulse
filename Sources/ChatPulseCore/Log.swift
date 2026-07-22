import Foundation

public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public struct LogEntry: Sendable {
    public let date: Date
    public let level: LogLevel
    public let message: String

    public init(date: Date = Date(), level: LogLevel, message: String) {
        self.date = date
        self.level = level
        self.message = message
    }
}

public final class RingLog: @unchecked Sendable {
    private let capacity: Int
    private var entries: [LogEntry] = []
    private let lock = NSLock()

    public init(capacity: Int = 200) {
        self.capacity = max(capacity, 1)
    }

    public func append(_ entry: LogEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    public func snapshot() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
