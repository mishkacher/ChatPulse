import XCTest
@testable import ChatPulseCore

final class ChatURLTests: XCTestCase {
    func testNormalizesCurrentChatGPTURL() {
        XCTAssertEqual(
            ChatURL.normalized("https://chatgpt.com/c/1234?temporary-chat=true#bottom"),
            "https://chatgpt.com/c/1234"
        )
    }

    func testMigratesLegacyHost() {
        XCTAssertEqual(
            ChatURL.normalized("https://chat.openai.com/c/abcd"),
            "https://chatgpt.com/c/abcd"
        )
    }

    func testSupportsGPTScopedChatURL() {
        XCTAssertEqual(
            ChatURL.normalized("https://chatgpt.com/g/g-example/c/abcd?model=test"),
            "https://chatgpt.com/g/g-example/c/abcd"
        )
    }

    func testRejectsHomepageAndForeignSites() {
        XCTAssertNil(ChatURL.normalized("https://chatgpt.com/"))
        XCTAssertNil(ChatURL.normalized("https://example.com/c/abcd"))
    }
}
