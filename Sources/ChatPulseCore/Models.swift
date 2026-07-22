import Foundation

public enum MessageRole: String, Codable, Sendable {
    case assistant
    case user
    case system
    case unknown
}

public struct BrowserSnapshot: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let latestRole: MessageRole
    public let latestFingerprint: String?
    public let isGenerating: Bool
    public let limitDetected: Bool
    public let errorDetected: Bool
    public let pageReady: Bool

    public init(
        title: String,
        url: String,
        latestRole: MessageRole,
        latestFingerprint: String?,
        isGenerating: Bool,
        limitDetected: Bool,
        errorDetected: Bool,
        pageReady: Bool = true
    ) {
        self.title = title
        self.url = url
        self.latestRole = latestRole
        self.latestFingerprint = latestFingerprint
        self.isGenerating = isGenerating
        self.limitDetected = limitDetected
        self.errorDetected = errorDetected
        self.pageReady = pageReady
    }
}

public struct MonitoredChat: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: String
    public var isEnabled: Bool
    public var lastObservedFingerprint: String?
    public var lastCommandedFingerprint: String?
    public var lastObservedAt: Date?
    public var lastCommandAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        url: String,
        isEnabled: Bool = true,
        lastObservedFingerprint: String? = nil,
        lastCommandedFingerprint: String? = nil,
        lastObservedAt: Date? = nil,
        lastCommandAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.isEnabled = isEnabled
        self.lastObservedFingerprint = lastObservedFingerprint
        self.lastCommandedFingerprint = lastCommandedFingerprint
        self.lastObservedAt = lastObservedAt
        self.lastCommandAt = lastCommandAt
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultCommand = "продолжай и не останавливайся до технического лимита"
    public static let defaultInterval: TimeInterval = 300

    public var checkIntervalSeconds: TimeInterval
    public var commandText: String
    public var chats: [MonitoredChat]

    public init(
        checkIntervalSeconds: TimeInterval = AppSettings.defaultInterval,
        commandText: String = AppSettings.defaultCommand,
        chats: [MonitoredChat] = []
    ) {
        self.checkIntervalSeconds = Self.clampedInterval(checkIntervalSeconds)
        self.commandText = commandText
        self.chats = chats
    }

    public static func clampedInterval(_ value: TimeInterval) -> TimeInterval {
        min(max(value, 30), 86_400)
    }
}

public enum MonitorDecision: Equatable, Sendable {
    case baselineRecorded
    case responseChanged
    case sendContinuation
    case waitingForAssistant
    case generating
    case technicalLimit
    case pageError
    case pageNotReady
    case noMessages
    case disabled
    case alreadyContinued
}

public struct EvaluationResult: Equatable, Sendable {
    public var chat: MonitoredChat
    public let decision: MonitorDecision

    public init(chat: MonitoredChat, decision: MonitorDecision) {
        self.chat = chat
        self.decision = decision
    }
}
