import XCTest
@testable import ChatPulseCore

final class LoginSupportTests: XCTestCase {
    func testOfficialLoginURLUsesChatGPTHTTPS() {
        XCTAssertEqual(LoginSupport.loginURL.scheme, "https")
        XCTAssertEqual(LoginSupport.loginURL.host, "chatgpt.com")
        XCTAssertEqual(LoginSupport.loginURL.path, "/auth/login")
    }

    func testEmailPreparationNeverReadsOrExportsCredentials() {
        let script = LoginSupport.emailCodePreparationJavaScript

        XCTAssertTrue(script.contains("input[type=\"email\"]"))
        XCTAssertTrue(script.contains("email-focused"))
        XCTAssertFalse(script.contains("fetch("))
        XCTAssertFalse(script.contains("XMLHttpRequest"))
        XCTAssertFalse(script.contains("localStorage.setItem"))
    }

    func testEmailCodeFallbackLooksForOfficialPageControls() {
        let script = LoginSupport.requestEmailCodeJavaScript

        XCTAssertTrue(script.contains("try with email"))
        XCTAssertTrue(script.contains("код.*почт"))
        XCTAssertTrue(script.contains("email-code-requested"))
    }

    func testPasskeyFlowUsesWebAuthnPlatformChecks() {
        let script = LoginSupport.passkeyPreparationJavaScript

        XCTAssertTrue(script.contains("PublicKeyCredential"))
        XCTAssertTrue(script.contains("isUserVerifyingPlatformAuthenticatorAvailable"))
        XCTAssertTrue(script.contains("isConditionalMediationAvailable"))
        XCTAssertTrue(script.contains("passkey-triggered"))
        XCTAssertFalse(script.contains("navigator.credentials.create"))
    }

    func testLikelySuccessfulLoginURLRejectsAuthPages() {
        XCTAssertFalse(LoginSupport.isLikelySuccessfulLoginURL(URL(string: "https://chatgpt.com/auth/login")))
        XCTAssertFalse(LoginSupport.isLikelySuccessfulLoginURL(URL(string: "https://auth.openai.com/u/login")))
        XCTAssertTrue(LoginSupport.isLikelySuccessfulLoginURL(URL(string: "https://chatgpt.com/")))
        XCTAssertTrue(LoginSupport.isLikelySuccessfulLoginURL(URL(string: "https://chatgpt.com/c/example")))
    }
}
