import XCTest
@testable import ChatPulseCore

final class DecisionEngineTests: XCTestCase {
    private let engine = DecisionEngine()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFirstObservationOnlyRecordsBaseline() {
        let result = engine.evaluate(
            chat: MonitoredChat(title: "Core", url: "https://chatgpt.com/c/abc"),
            snapshot: snapshot(role: .assistant, fingerprint: "answer-1"),
            now: now,
            isFirstObservationThisRun: true
        )
        XCTAssertEqual(result.decision, .baselineRecorded)
        XCTAssertEqual(result.chat.lastObservedFingerprint, "answer-1")
    }

    func testChangedAssistantResponseIsNotImmediatelyContinued() {
        let chat = MonitoredChat(
            title: "Core",
            url: "https://chatgpt.com/c/abc",
            lastObservedFingerprint: "answer-1",
            lastCommandedFingerprint: "answer-1"
        )
        let result = engine.evaluate(
            chat: chat,
            snapshot: snapshot(role: .assistant, fingerprint: "answer-2"),
            now: now,
            isFirstObservationThisRun: false
        )
        XCTAssertEqual(result.decision, .responseChanged)
        XCTAssertEqual(result.chat.lastObservedFingerprint, "answer-2")
    }

    func testStableCompletedAssistantResponseIsContinuedOnNextCheck() {
        let chat = MonitoredChat(
            title: "Core",
            url: "https://chatgpt.com/c/abc",
            lastObservedFingerprint: "answer-2",
            lastCommandedFingerprint: "answer-1"
        )
        let result = engine.evaluate(
            chat: chat,
            snapshot: snapshot(role: .assistant, fingerprint: "answer-2"),
            now: now,
            isFirstObservationThisRun: false
        )
        XCTAssertEqual(result.decision, .sendContinuation)
    }

    func testSameAssistantResponseIsNeverContinuedTwice() {
        let chat = MonitoredChat(
            title: "Core",
            url: "https://chatgpt.com/c/abc",
            lastObservedFingerprint: "answer-2",
            lastCommandedFingerprint: "answer-2"
        )
        let result = engine.evaluate(
            chat: chat,
            snapshot: snapshot(role: .assistant, fingerprint: "answer-2"),
            now: now,
            isFirstObservationThisRun: false
        )
        XCTAssertEqual(result.decision, .alreadyContinued)
    }

    func testUserMessageWaitsForAssistant() {
        let chat = MonitoredChat(
            title: "Core",
            url: "https://chatgpt.com/c/abc",
            lastObservedFingerprint: "command-1"
        )
        let result = engine.evaluate(
            chat: chat,
            snapshot: snapshot(role: .user, fingerprint: "command-1"),
            now: now,
            isFirstObservationThisRun: false
        )
        XCTAssertEqual(result.decision, .waitingForAssistant)
    }

    func testGenerationLimitErrorAndDisabledStatesNeverSend() {
        let baseChat = MonitoredChat(title: "Core", url: "https://chatgpt.com/c/abc")
        XCTAssertEqual(
            engine.evaluate(
                chat: baseChat,
                snapshot: snapshot(role: .assistant, fingerprint: "a", generating: true),
                now: now,
                isFirstObservationThisRun: false
            ).decision,
            .generating
        )
        XCTAssertEqual(
            engine.evaluate(
                chat: baseChat,
                snapshot: snapshot(role: .assistant, fingerprint: "a", limit: true),
                now: now,
                isFirstObservationThisRun: false
            ).decision,
            .technicalLimit
        )
        XCTAssertEqual(
            engine.evaluate(
                chat: baseChat,
                snapshot: snapshot(role: .assistant, fingerprint: "a", error: true),
                now: now,
                isFirstObservationThisRun: false
            ).decision,
            .pageError
        )
        XCTAssertEqual(
            engine.evaluate(
                chat: MonitoredChat(title: "Core", url: baseChat.url, isEnabled: false),
                snapshot: snapshot(role: .assistant, fingerprint: "a"),
                now: now,
                isFirstObservationThisRun: false
            ).decision,
            .disabled
        )
    }

    func testSuccessfulSendStoresFingerprintAndTimestamp() {
        let chat = engine.recordSuccessfulSend(
            chat: MonitoredChat(title: "Core", url: "https://chatgpt.com/c/abc"),
            fingerprint: "answer-2",
            now: now
        )
        XCTAssertEqual(chat.lastCommandedFingerprint, "answer-2")
        XCTAssertEqual(chat.lastCommandAt, now)
    }

    func testFullCycleWaitsOneIntervalAfterEveryNewAssistantResponse() {
        var chat = MonitoredChat(title: "Core", url: "https://chatgpt.com/c/abc")

        var result = engine.evaluate(
            chat: chat,
            snapshot: snapshot(role: .assistant, fingerprint: "answer-1"),
            now: now,
            isFirstObservationThisRun: true
        )
        XCTAssertEqual(result.decision, .baselineRecorded)
        chat = result.chat

        result = engine.evaluate(
            chat: chat,
            snapshot: snapshot(role: .assistant, fingerprint: "answer-1"),
            now: now.addingTimeInterval(300),
            isFirstObservationThisRun: false
        )
        XCTAssertEqual(result.decision, .sendContinuation)
        chat = engine.recordSuccessfulSend(
            chat: result.chat,
            fingerprint: "answer-1",
            now: now.addingTimeInterval(300)
        )

        result = engine.evaluate(
            chat: chat,
            snapshot: snapshot(role: .assistant, fingerprint: "answer-2"),
            now: now.addingTimeInterval(600),
            isFirstObservationThisRun: false
        )
        XCTAssertEqual(result.decision, .responseChanged)
        chat = result.chat

        result = engine.evaluate(
            chat: chat,
            snapshot: snapshot(role: .assistant, fingerprint: "answer-2"),
            now: now.addingTimeInterval(900),
            isFirstObservationThisRun: false
        )
        XCTAssertEqual(result.decision, .sendContinuation)
    }

    func testPageNotReadyAndEmptyPageNeverSend() {
        let chat = MonitoredChat(title: "Core", url: "https://chatgpt.com/c/abc")
        let notReady = BrowserSnapshot(
            title: "Core",
            url: chat.url,
            latestRole: .assistant,
            latestFingerprint: "answer",
            isGenerating: false,
            limitDetected: false,
            errorDetected: false,
            pageReady: false
        )
        XCTAssertEqual(
            engine.evaluate(chat: chat, snapshot: notReady, now: now, isFirstObservationThisRun: false).decision,
            .pageNotReady
        )
        XCTAssertEqual(
            engine.evaluate(
                chat: chat,
                snapshot: snapshot(role: .unknown, fingerprint: nil),
                now: now,
                isFirstObservationThisRun: false
            ).decision,
            .noMessages
        )
    }

    private func snapshot(
        role: MessageRole,
        fingerprint: String?,
        generating: Bool = false,
        limit: Bool = false,
        error: Bool = false
    ) -> BrowserSnapshot {
        BrowserSnapshot(
            title: "Core",
            url: "https://chatgpt.com/c/abc",
            latestRole: role,
            latestFingerprint: fingerprint,
            isGenerating: generating,
            limitDetected: limit,
            errorDetected: error
        )
    }
}
