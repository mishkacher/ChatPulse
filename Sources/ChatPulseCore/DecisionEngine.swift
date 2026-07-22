import Foundation

public struct DecisionEngine: Sendable {
    public init() {}

    /// Evaluates a single completed browser observation.
    ///
    /// The first observation in every application run is always a baseline. This prevents
    /// ChatPulse from sending a continuation immediately after launch. A continuation is sent
    /// only when the same completed assistant message is observed again on a later check.
    public func evaluate(
        chat original: MonitoredChat,
        snapshot: BrowserSnapshot,
        now: Date,
        isFirstObservationThisRun: Bool
    ) -> EvaluationResult {
        var chat = original

        guard chat.isEnabled else {
            return EvaluationResult(chat: chat, decision: .disabled)
        }

        chat.lastObservedAt = now

        guard snapshot.pageReady else {
            return EvaluationResult(chat: chat, decision: .pageNotReady)
        }

        if snapshot.limitDetected {
            return EvaluationResult(chat: chat, decision: .technicalLimit)
        }

        if snapshot.errorDetected {
            return EvaluationResult(chat: chat, decision: .pageError)
        }

        if snapshot.isGenerating {
            return EvaluationResult(chat: chat, decision: .generating)
        }

        guard let fingerprint = snapshot.latestFingerprint, !fingerprint.isEmpty else {
            return EvaluationResult(chat: chat, decision: .noMessages)
        }

        if isFirstObservationThisRun {
            chat.lastObservedFingerprint = fingerprint
            return EvaluationResult(chat: chat, decision: .baselineRecorded)
        }

        if chat.lastObservedFingerprint != fingerprint {
            chat.lastObservedFingerprint = fingerprint
            return EvaluationResult(chat: chat, decision: .responseChanged)
        }

        guard snapshot.latestRole == .assistant else {
            return EvaluationResult(chat: chat, decision: .waitingForAssistant)
        }

        if chat.lastCommandedFingerprint == fingerprint {
            return EvaluationResult(chat: chat, decision: .alreadyContinued)
        }

        return EvaluationResult(chat: chat, decision: .sendContinuation)
    }

    public func recordSuccessfulSend(
        chat original: MonitoredChat,
        fingerprint: String,
        now: Date
    ) -> MonitoredChat {
        var chat = original
        chat.lastCommandedFingerprint = fingerprint
        chat.lastCommandAt = now
        return chat
    }
}
