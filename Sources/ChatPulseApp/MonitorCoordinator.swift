#if canImport(AppKit)
import Foundation
import ChatPulseCore

struct MonitorStatus {
    enum State {
        case stopped
        case idle
        case checking
        case sent(chatTitle: String)
        case warning(String)
    }

    let state: State
    let checkedAt: Date?
    let nextCheckAt: Date?
}

@MainActor
final class MonitorCoordinator {
    private let store: SettingsStoring
    private let browser: BrowserControlling
    private let engine = DecisionEngine()
    private let log: RingLog

    private var timer: Timer?
    private var checkTask: Task<Void, Never>?
    private var isChecking = false
    private var firstObservationIDs = Set<UUID>()

    private(set) var isRunning = false
    var onStatus: ((MonitorStatus) -> Void)?
    var onSettingsChanged: ((AppSettings) -> Void)?

    init(store: SettingsStoring, browser: BrowserControlling, log: RingLog) {
        self.store = store
        self.browser = browser
        self.log = log
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        firstObservationIDs.removeAll()
        log.append(LogEntry(level: .info, message: "Наблюдение запущено"))
        scheduleTimer(runImmediately: true)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        checkTask?.cancel()
        log.append(LogEntry(level: .info, message: "Наблюдение остановлено"))
        publish(MonitorStatus(state: .stopped, checkedAt: nil, nextCheckAt: nil))
    }

    func reschedule() {
        guard isRunning else { return }
        scheduleTimer(runImmediately: false)
    }

    func checkNow() {
        launchCheck(ignoreRunningState: true)
    }

    private func scheduleTimer(runImmediately: Bool) {
        timer?.invalidate()

        let settings: AppSettings
        do {
            settings = try store.load()
        } catch {
            publish(MonitorStatus(state: .warning(error.localizedDescription), checkedAt: nil, nextCheckAt: nil))
            return
        }

        let interval = AppSettings.clampedInterval(settings.checkIntervalSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.launchCheck(ignoreRunningState: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let delay = runImmediately ? 0.1 : interval
        publish(MonitorStatus(
            state: .idle,
            checkedAt: nil,
            nextCheckAt: Date().addingTimeInterval(delay)
        ))

        if runImmediately {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self?.launchCheck(ignoreRunningState: false)
            }
        }
    }

    private func launchCheck(ignoreRunningState: Bool) {
        guard (isRunning || ignoreRunningState), !isChecking else { return }
        isChecking = true
        checkTask = Task { @MainActor [weak self] in
            await self?.performCheck(ignoreRunningState: ignoreRunningState)
        }
    }

    private func performCheck(ignoreRunningState: Bool) async {
        defer {
            isChecking = false
            checkTask = nil
        }

        publish(MonitorStatus(state: .checking, checkedAt: nil, nextCheckAt: nil))

        do {
            var observedSettings = try store.load()
            let now = Date()
            var notableState: MonitorStatus.State = .idle

            for index in observedSettings.chats.indices where observedSettings.chats[index].isEnabled {
                if Task.isCancelled { break }
                var chat = observedSettings.chats[index]

                do {
                    let snapshot = try await browser.inspect(chat: chat)
                    let isFirst = !firstObservationIDs.contains(chat.id)
                    let result = engine.evaluate(
                        chat: chat,
                        snapshot: snapshot,
                        now: now,
                        isFirstObservationThisRun: isFirst
                    )
                    firstObservationIDs.insert(chat.id)
                    chat = result.chat

                    switch result.decision {
                    case .sendContinuation:
                        guard let fingerprint = snapshot.latestFingerprint else { break }
                        guard !Task.isCancelled, ignoreRunningState || isRunning else {
                            log.append(LogEntry(level: .info, message: "Отправка отменена: наблюдение остановлено"))
                            break
                        }

                        // Пользователь мог удалить или отключить чат, пока WebKit ожидал загрузку.
                        // Перед отправкой перечитываем актуальные настройки и не действуем по старому снимку.
                        let liveSettings = try store.load()
                        guard liveSettings.chats.contains(where: { $0.id == chat.id && $0.isEnabled }) else {
                            log.append(LogEntry(
                                level: .info,
                                message: "Отправка отменена: чат «\(chat.title)» удалён или отключён"
                            ))
                            break
                        }

                        let outcome = try await browser.send(command: liveSettings.commandText, to: chat)
                        chat = engine.recordDispatchedCommand(
                            chat: chat,
                            fingerprint: fingerprint,
                            now: now,
                            outcome: outcome
                        )

                        switch outcome {
                        case .confirmed:
                            notableState = .sent(chatTitle: chat.title)
                            log.append(LogEntry(
                                level: .info,
                                message: "Команда продолжения отправлена в «\(chat.title)»"
                            ))
                        case .submittedUnconfirmed:
                            notableState = .warning(
                                "Команда отправлена в «\(chat.title)», но интерфейс не подтвердил её появление"
                            )
                            log.append(LogEntry(
                                level: .warning,
                                message: "Кнопка отправки нажата в «\(chat.title)», подтверждение DOM не получено; повтор заблокирован"
                            ))
                        }
                    case .pageError:
                        notableState = .warning("Ошибка страницы: \(chat.title)")
                        log.append(LogEntry(level: .warning, message: "На странице чата «\(chat.title)» обнаружена ошибка"))
                    default:
                        log.append(LogEntry(
                            level: .debug,
                            message: "\(chat.title): \(russianDescription(for: result.decision))"
                        ))
                    }

                    observedSettings.chats[index] = chat
                } catch {
                    notableState = .warning(error.localizedDescription)
                    log.append(LogEntry(level: .error, message: "\(chat.title): \(error.localizedDescription)"))
                }
            }

            // Не сохраняем старый снимок целиком. Пока выполнялись await-вызовы,
            // пользователь мог изменить интервал, список чатов или их включённое состояние.
            let latestSettings = try store.load()
            let mergedSettings = SettingsMerger.mergeRuntimeState(
                from: observedSettings,
                into: latestSettings
            )
            try store.save(mergedSettings)
            onSettingsChanged?(mergedSettings)
            publish(MonitorStatus(
                state: notableState,
                checkedAt: now,
                nextCheckAt: isRunning ? now.addingTimeInterval(mergedSettings.checkIntervalSeconds) : nil
            ))
        } catch {
            log.append(LogEntry(level: .error, message: error.localizedDescription))
            publish(MonitorStatus(state: .warning(error.localizedDescription), checkedAt: Date(), nextCheckAt: nil))
        }
    }

    private func russianDescription(for decision: MonitorDecision) -> String {
        switch decision {
        case .baselineRecorded:
            return "зафиксировано исходное состояние"
        case .responseChanged:
            return "обнаружен новый ответ, ожидается следующая проверка"
        case .sendContinuation:
            return "нужно отправить продолжение"
        case .waitingForAssistant:
            return "последнее сообщение принадлежит пользователю"
        case .generating:
            return "ответ ещё создаётся"
        case .pageError:
            return "ошибка страницы"
        case .pageNotReady:
            return "страница ещё не готова"
        case .noMessages:
            return "сообщения не найдены"
        case .disabled:
            return "чат отключён"
        case .alreadyContinued:
            return "этот ответ уже продолжен"
        }
    }

    private func publish(_ status: MonitorStatus) {
        onStatus?(status)
    }
}
#endif
