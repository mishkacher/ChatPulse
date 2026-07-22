import XCTest
@testable import ChatPulseCore

final class AppSkinTests: XCTestCase {
    func testAllExpectedSkinsAreAvailable() {
        XCTAssertEqual(AppSkin.allCases, [.macOS, .chatPulsePreview])
    }

    func testDisplayNamesAreStableAndUserFacing() {
        XCTAssertEqual(AppSkin.macOS.displayName, "macOS")
        XCTAssertEqual(AppSkin.chatPulsePreview.displayName, "ChatPulse Preview")
    }

    func testSkinCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for skin in AppSkin.allCases {
            let data = try encoder.encode(skin)
            let decoded = try decoder.decode(AppSkin.self, from: data)
            XCTAssertEqual(decoded, skin)
        }
    }

    func testRawValuesRemainSuitableForUserDefaults() {
        XCTAssertEqual(AppSkin.macOS.rawValue, "macOS")
        XCTAssertEqual(AppSkin.chatPulsePreview.rawValue, "chatPulsePreview")
    }
}
