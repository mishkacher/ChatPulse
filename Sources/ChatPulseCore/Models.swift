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
    public let errorDetected: Bool
    public let pageReady: Bool

    public init(
        title: String,
        url: String,
        latestRole: MessageRole,
        latestFingerprint: String?,
        isGenerating: Bool,
        errorDetected: Bool,
        pageReady: Bool = true
    ) {
        self.title = title
        self.url = url
        self.latestRole = latestRole
        self.latestFingerprint = latestFingerprint
        self.isGenerating = isGenerating
        self.errorDetected = errorDetected
        self.pageReady = pageReady
    }
}

/// Результат попытки отправки после фактического нажатия кнопки.
///
/// Оба варианта означают, что повторять команду для того же ответа нельзя:
/// интерфейс мог принять сообщение, даже если DOM-подтверждение не успело появиться.
public enum CommandSendOutcome: String, Codable, Equatable, Sendable {
    case confirmed
    case submittedUnconfirmed
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
    public var lastCommandOutcome: CommandSendOutcome?

    public init(
        id: UUID = UUID(),
        title: String,
        url: String,
        isEnabled: Bool = true,
        lastObservedFingerprint: String? = nil,
        lastCommandedFingerprint: String? = nil,
        lastObservedAt: Date? = nil,
        lastCommandAt: Date? = nil,
        lastCommandOutcome: CommandSendOutcome? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.isEnabled = isEnabled
        self.lastObservedFingerprint = lastObservedFingerprint
        self.lastCommandedFingerprint = lastCommandedFingerprint
        self.lastObservedAt = lastObservedAt
        self.lastCommandAt = lastCommandAt
        self.lastCommandOutcome = lastCommandOutcome
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultCommand = "продолжай и не останавливайся до технического лимита"
    public static let defaultInterval: TimeInterval = 300
    public static let defaultSkin: AppSkin = .macOS

    public var checkIntervalSeconds: TimeInterval
    public var commandText: String
    public var chats: [MonitoredChat]
    public var skin: AppSkin

    public init(
        checkIntervalSeconds: TimeInterval = AppSettings.defaultInterval,
        commandText: String = AppSettings.defaultCommand,
        chats: [MonitoredChat] = [],
        skin: AppSkin = AppSettings.defaultSkin
    ) {
        self.checkIntervalSeconds = Self.clampedInterval(checkIntervalSeconds)
        self.commandText = commandText
        self.chats = chats
        self.skin = skin
    }

    public static func clampedInterval(_ value: TimeInterval) -> TimeInterval {
        min(max(value, 30), 86_400)
    }

    private enum CodingKeys: String, CodingKey {
        case checkIntervalSeconds
        case commandText
        case chats
        case skin
    }

    /// Старые `settings.json` не содержали ключ `skin`. При чтении таких файлов
    /// используется нативный стиль macOS, поэтому обновление не сбрасывает чаты.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkIntervalSeconds = Self.clampedInterval(
            try container.decodeIfPresent(TimeInterval.self, forKey: .checkIntervalSeconds)
                ?? Self.defaultInterval
        )
        commandText = try container.decodeIfPresent(String.self, forKey: .commandText)
            ?? Self.defaultCommand
        chats = try container.decodeIfPresent([MonitoredChat].self, forKey: .chats) ?? []
        skin = try container.decodeIfPresent(AppSkin.self, forKey: .skin) ?? Self.defaultSkin
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checkIntervalSeconds, forKey: .checkIntervalSeconds)
        try container.encode(commandText, forKey: .commandText)
        try container.encode(chats, forKey: .chats)
        try container.encode(skin, forKey: .skin)
    }
}

public enum MonitorDecision: Equatable, Sendable {
    case baselineRecorded
    case responseChanged
    case sendContinuation
    case waitingForAssistant
    case generating
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
