import Foundation

public struct DecisionEngine: Sendable {
    public init() {}

    /// Оценивает одно завершённое наблюдение браузера.
    ///
    /// Первая проверка после каждого запуска всегда только фиксирует исходное состояние.
    /// Команда отправляется лишь тогда, когда один и тот же завершённый ответ ассистента
    /// обнаружен повторно на следующей проверке.
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

    /// Фиксирует команду после фактического нажатия кнопки отправки.
    ///
    /// Даже если DOM-подтверждение не успело появиться, отпечаток считается обработанным.
    /// Это обеспечивает at-most-once поведение и исключает повторную команду после
    /// неопределённого результата интерфейса.
    public func recordDispatchedCommand(
        chat original: MonitoredChat,
        fingerprint: String,
        now: Date,
        outcome: CommandSendOutcome
    ) -> MonitoredChat {
        var chat = original
        chat.lastCommandedFingerprint = fingerprint
        chat.lastCommandAt = now
        chat.lastCommandOutcome = outcome
        return chat
    }
}
