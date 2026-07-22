import Foundation

public protocol SettingsStoring: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

public enum SettingsStoreError: LocalizedError {
    case invalidDirectory

    public var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            return "Не удалось определить папку Application Support."
        }
    }
}

public final class JSONSettingsStore: SettingsStoring, @unchecked Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let lock = NSLock()

    public convenience init(fileManager: FileManager = .default) throws {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SettingsStoreError.invalidDirectory
        }

        let directory = applicationSupport.appendingPathComponent("ChatPulse", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.init(fileURL: directory.appendingPathComponent("settings.json"), fileManager: fileManager)
    }

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> AppSettings {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }

        let data = try Data(contentsOf: fileURL)
        var settings = try decoder.decode(AppSettings.self, from: data)
        settings.checkIntervalSeconds = AppSettings.clampedInterval(settings.checkIntervalSeconds)
        if settings.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.commandText = AppSettings.defaultCommand
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        lock.lock()
        defer { lock.unlock() }

        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
    }
}
