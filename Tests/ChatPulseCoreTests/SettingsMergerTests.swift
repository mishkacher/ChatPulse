import XCTest
@testable import ChatPulseCore

final class SettingsMergerTests: XCTestCase {
    func testPreservesLatestUserConfigurationAndMergesRuntimeState() throws {
        let chatID = UUID()
        let addedChatID = UUID()
        let observedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let commandedAt = Date(timeIntervalSince1970: 1_700_000_200)

        let observed = AppSettings(
            checkIntervalSeconds: 300,
            commandText: "старая команда",
            chats: [
                MonitoredChat(
                    id: chatID,
                    title: "Старое название",
                    url: "https://chatgpt.com/c/example",
                    isEnabled: true,
                    lastObservedFingerprint: "answer-2",
                    lastCommandedFingerprint: "answer-1",
                    lastObservedAt: observedAt,
                    lastCommandAt: commandedAt
                )
            ]
        )

        let latest = AppSettings(
            checkIntervalSeconds: 900,
            commandText: "новая команда",
            chats: [
                MonitoredChat(
                    id: chatID,
                    title: "Новое название",
                    url: "https://chatgpt.com/c/example",
                    isEnabled: false
                ),
                MonitoredChat(
                    id: addedChatID,
                    title: "Добавленный чат",
                    url: "https://chatgpt.com/c/added"
                )
            ]
        )

        let merged = SettingsMerger.mergeRuntimeState(from: observed, into: latest)

        XCTAssertEqual(merged.checkIntervalSeconds, 900)
        XCTAssertEqual(merged.commandText, "новая команда")
        XCTAssertEqual(merged.chats.count, 2)

        let existing = try XCTUnwrap(merged.chats.first { $0.id == chatID })
        XCTAssertEqual(existing.title, "Новое название")
        XCTAssertFalse(existing.isEnabled)
        XCTAssertEqual(existing.lastObservedFingerprint, "answer-2")
        XCTAssertEqual(existing.lastCommandedFingerprint, "answer-1")
        XCTAssertEqual(existing.lastObservedAt, observedAt)
        XCTAssertEqual(existing.lastCommandAt, commandedAt)

        let added = try XCTUnwrap(merged.chats.first { $0.id == addedChatID })
        XCTAssertNil(added.lastObservedFingerprint)
        XCTAssertNil(added.lastCommandedFingerprint)
    }

    func testDoesNotRestoreChatDeletedDuringCheck() {
        let deletedID = UUID()
        let observed = AppSettings(
            chats: [
                MonitoredChat(
                    id: deletedID,
                    title: "Удалённый чат",
                    url: "https://chatgpt.com/c/deleted",
                    lastObservedFingerprint: "answer"
                )
            ]
        )
        let latest = AppSettings(chats: [])

        let merged = SettingsMerger.mergeRuntimeState(from: observed, into: latest)

        XCTAssertTrue(merged.chats.isEmpty)
    }

    func testLeavesNewChatUntouched() throws {
        let newID = UUID()
        let latest = AppSettings(
            chats: [
                MonitoredChat(
                    id: newID,
                    title: "Новый чат",
                    url: "https://chatgpt.com/c/new"
                )
            ]
        )

        let merged = SettingsMerger.mergeRuntimeState(from: AppSettings(), into: latest)
        let chat = try XCTUnwrap(merged.chats.first)

        XCTAssertEqual(chat.id, newID)
        XCTAssertNil(chat.lastObservedFingerprint)
        XCTAssertNil(chat.lastCommandedFingerprint)
    }
}
