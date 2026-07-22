#if canImport(AppKit)
import Foundation
import ChatPulseCore

struct MonitorStatus: Sendable {
    enum State: Sendable {
        case stopped
        case idle
        case checking
        case sent(chatTitle: String)
        case limit(chatTitle: String)
        case warning(String)
    }

    let state: State
    let checkedAt: Date?
    let nextCheckAt: Date?
}

final class MonitorCoordinator: @unchecked Sendable {
    private let store: SettingsStoring
    private let browser: BrowserControlling
    private let engine = DecisionEngine()
    private let log: RingLog
    private let workQueue = DispatchQueue(label: "app.chatpulse.monitor", qos: .utility)
    private let lock = NSLock()

    private var timer: DispatchSourceTimer?
    private var isRunningStorage = false
    private var isCheckingStorage = false
    private var firstObservationIDs = Set<UUID>()

    var onStatus: (@Sendable (MonitorStatus) -> Void)?
    var onSettingsChanged: (@Sendable (AppSettings) -> Void)?

    init(store: SettingsStoring, browser: BrowserControlling, log: RingLog) {
        self.store = store
        self.browser = browser
        self.log = log
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunningStorage
    }

    func start() {
        lock.lock()
        guard !isRunningStorage else {
            lock.unlock()
            return
        }
        isRunningStorage = true
        lock.unlock()

        workQueue.sync { [self] in
            firstObservationIDs.removeAll()
        }

        log.append(LogEntry(level: .info, message: "Monitoring started"))
        scheduleTimer(runImmediately: true)
    }

    func stop() {
        lock.lock()
        isRunningStorage = false
        let oldTimer = timer
        timer = nil
        lock.unlock()

        oldTimer?.cancel()
        log.append(LogEntry(level: .info, message: "Monitoring stopped"))
        publish(MonitorStatus(state: .stopped, checkedAt: nil, nextCheckAt: nil))
    }

    func reschedule() {
        guard isRunning else { return }
        scheduleTimer(runImmediately: false)
    }

    func checkNow() {
        performCheck(ignoreRunningState: true)
    }

    private func scheduleTimer(runImmediately: Bool) {
        let settings: AppSettings
        do {
            settings = try store.load()
        } catch {
            publish(MonitorStatus(state: .warning(error.localizedDescription), checkedAt: nil, nextCheckAt: nil))
            return
        }

        let interval = AppSettings.clampedInterval(settings.checkIntervalSeconds)
        let source = DispatchSource.makeTimerSource(queue: workQueue)
        source.schedule(
            deadline: .now() + (runImmediately ? 0.1 : interval),
            repeating: interval,
            leeway: .seconds(min(Int(interval / 10), 10))
        )
        source.setEventHandler { [weak self] in
            self?.performCheck(ignoreRunningState: false)
        }

        lock.lock()
        let oldTimer = timer
        timer = source
        lock.unlock()

        oldTimer?.cancel()
        source.resume()
        publish(MonitorStatus(
            state: .idle,
            checkedAt: nil,
            nextCheckAt: Date().addingTimeInterval(runImmediately ? 0.1 : interval)
        ))
    }

    private func performCheck(ignoreRunningState: Bool) {
        lock.lock()
        let allowed = (isRunningStorage || ignoreRunningState) && !isCheckingStorage
        if allowed { isCheckingStorage = true }
        lock.unlock()
        guard allowed else { return }

        workQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.isCheckingStorage = false
                self.lock.unlock()
            }

            self.publish(MonitorStatus(state: .checking, checkedAt: nil, nextCheckAt: nil))

            do {
                var settings = try self.store.load()
                let now = Date()
                var notableState: MonitorStatus.State = .idle

                for index in settings.chats.indices where settings.chats[index].isEnabled {
                    var chat = settings.chats[index]
                    do {
                        let snapshot = try self.browser.inspect(chat: chat)
                        let isFirst = !self.firstObservationIDs.contains(chat.id)
                        let result = self.engine.evaluate(
                            chat: chat,
                            snapshot: snapshot,
                            now: now,
                            isFirstObservationThisRun: isFirst
                        )
                        self.firstObservationIDs.insert(chat.id)
                        chat = result.chat

                        switch result.decision {
                        case .sendContinuation:
                            guard let fingerprint = snapshot.latestFingerprint else { break }
                            if !ignoreRunningState && !self.isRunning {
                                self.log.append(LogEntry(level: .info, message: "Send cancelled because monitoring stopped"))
                                break
                            }
                            try self.browser.send(command: settings.commandText, to: chat)
                            chat = self.engine.recordSuccessfulSend(
                                chat: chat,
                                fingerprint: fingerprint,
                                now: now
                            )
                            notableState = .sent(chatTitle: chat.title)
                            self.log.append(LogEntry(level: .info, message: "Continuation sent to \(chat.title)"))
                        case .technicalLimit:
                            notableState = .limit(chatTitle: chat.title)
                            self.log.append(LogEntry(level: .warning, message: "Technical limit detected in \(chat.title)"))
                        case .pageError:
                            notableState = .warning("Ошибка страницы: \(chat.title)")
                            self.log.append(LogEntry(level: .warning, message: "Page error in \(chat.title)"))
                        default:
                            self.log.append(LogEntry(level: .debug, message: "\(chat.title): \(String(describing: result.decision))"))
                        }

                        settings.chats[index] = chat
                    } catch {
                        notableState = .warning(error.localizedDescription)
                        self.log.append(LogEntry(level: .error, message: "\(chat.title): \(error.localizedDescription)"))
                    }
                }

                try self.store.save(settings)
                self.onSettingsChanged?(settings)
                self.publish(MonitorStatus(
                    state: notableState,
                    checkedAt: now,
                    nextCheckAt: self.isRunning ? now.addingTimeInterval(settings.checkIntervalSeconds) : nil
                ))
            } catch {
                self.log.append(LogEntry(level: .error, message: error.localizedDescription))
                self.publish(MonitorStatus(state: .warning(error.localizedDescription), checkedAt: Date(), nextCheckAt: nil))
            }
        }
    }

    private func publish(_ status: MonitorStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(status)
        }
    }
}
#endif
