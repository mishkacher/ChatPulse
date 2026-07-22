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
                    lastCommandedFingerprint: "previous"
                )
            ]
        )

        try store.save(settings)
        let loaded = try store.load()

        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.commandText, "продолжай и не останавливайся до технического лимита")
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
