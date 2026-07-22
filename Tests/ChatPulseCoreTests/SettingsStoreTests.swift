import XCTest
@testable import ChatPulseCore

final class SettingsStoreTests: XCTestCase {
    func testRoundTripPreservesChatStateAndExactCommand() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let settings = AppSettings(
            checkIntervalSeconds: 300,
            commandText: AppSettings.defaultCommand,
            chats: [
                MonitoredChat(
                    title: "Модуль FVG",
                    url: "https://chatgpt.com/c/test",
                    lastObservedFingerprint: "response",
                    lastCommandedFingerprint: "previous",
                    lastCommandOutcome: .submittedUnconfirmed
                )
            ]
        )

        try store.save(settings)
        let loaded = try store.load()

        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.commandText, "продолжай и не останавливайся до технического лимита")
        XCTAssertEqual(loaded.chats.first?.lastCommandOutcome, .submittedUnconfirmed)
    }

    func testLegacySettingsWithoutOutcomeRemainReadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("settings.json")
        let chatID = UUID()
        let legacyJSON = """
        {
          "checkIntervalSeconds": 300,
          "commandText": "продолжай и не останавливайся до технического лимита",
          "chats": [
            {
              "id": "\(chatID.uuidString)",
              "title": "Старый чат",
              "url": "https://chatgpt.com/c/legacy",
              "isEnabled": true
            }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL, options: .atomic)

        let loaded = try JSONSettingsStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded.chats.first?.id, chatID)
        XCTAssertNil(loaded.chats.first?.lastCommandOutcome)
    }

    func testMissingFileReturnsDefaults() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: fileURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded.checkIntervalSeconds, 300)
        XCTAssertEqual(loaded.commandText, AppSettings.defaultCommand)
        XCTAssertTrue(loaded.chats.isEmpty)
    }

    func testIntervalIsClamped() {
        XCTAssertEqual(AppSettings.clampedInterval(1), 30)
        XCTAssertEqual(AppSettings.clampedInterval(300), 300)
        XCTAssertEqual(AppSettings.clampedInterval(100_000), 86_400)
    }
}
