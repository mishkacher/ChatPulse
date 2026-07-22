import XCTest
@testable import ChatPulseCore

final class AuthenticationURLTests: XCTestCase {
    func testRecognizesGoogleAccountsHost() {
        XCTAssertTrue(
            AuthenticationURL.isGoogleSignIn(
                "https://accounts.google.com/o/oauth2/v2/auth?client_id=example"
            )
        )
    }

    func testRecognizesGoogleProviderInsideOpenAIAuthenticationURL() {
        XCTAssertTrue(
            AuthenticationURL.isGoogleSignIn(
                "https://auth.openai.com/authorize?connection=google-oauth2&client_id=example"
            )
        )
        XCTAssertTrue(
            AuthenticationURL.isGoogleSignIn(
                "https://auth0.openai.com/login/social?provider=google"
            )
        )
    }

    func testDoesNotClassifyOtherProvidersOrNormalChatPages() {
        XCTAssertFalse(
            AuthenticationURL.isGoogleSignIn(
                "https://auth.openai.com/authorize?connection=apple"
            )
        )
        XCTAssertFalse(
            AuthenticationURL.isGoogleSignIn(
                "https://chatgpt.com/c/example"
            )
        )
        XCTAssertFalse(AuthenticationURL.isGoogleSignIn("about:blank"))
    }
}
