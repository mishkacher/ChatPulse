#if canImport(AppKit)
import AppKit
import Foundation
import ChatPulseCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var intervalMenuItem: NSMenuItem!
    private var chatsMenuItem: NSMenuItem!
    private var checkNowMenuItem: NSMenuItem!

    private let store: JSONSettingsStore
    private let browser: WebKitBrowserController
    private let log: RingLog
    private let coordinator: MonitorCoordinator
    private var settings: AppSettings
    private var monitorStatus = MonitorStatus(state: .stopped, checkedAt: nil, nextCheckAt: nil)

    override init() {
        let browser = WebKitBrowserController()
        let log = RingLog(capacity: 300)
        let resolvedStore: JSONSettingsStore
        let resolvedSettings: AppSettings

        do {
            resolvedStore = try JSONSettingsStore()
            do {
                resolvedSettings = try resolvedStore.load()
            } catch {
                resolvedSettings = AppSettings()
                try? resolvedStore.save(resolvedSettings)
                log.append(LogEntry(
                    level: .warning,
                    message: "Повреждённые настройки сброшены: \(error.localizedDescription)"
                ))
            }
        } catch {
            let fallbackURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ChatPulse-settings.json")
            resolvedStore = JSONSettingsStore(fileURL: fallbackURL)
            resolvedSettings = (try? resolvedStore.load()) ?? AppSettings()
            log.append(LogEntry(
                level: .warning,
                message: "Используется временное хранилище настроек: \(error.localizedDescription)"
            ))
        }

        self.browser = browser
        self.log = log
        self.store = resolvedStore
        self.settings = resolvedSettings
        self.coordinator = MonitorCoordinator(store: resolvedStore, browser: browser, log: log)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureCallbacks()
        rebuildMenu()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform.path.ecg",
            accessibilityDescription: "ChatPulse"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = menu
    }

    private func configureCallbacks() {
        coordinator.onStatus = { [weak self] status in
            self?.monitorStatus = status
            self?.refreshDynamicMenuItems()
        }
        coordinator.onSettingsChanged = { [weak self] settings in
            self?.settings = settings
            self?.rebuildChatsSubmenu()
        }
        browser.onAddCurrentChat = { [weak self] in
            self?.addCurrentChatFromBrowser()
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        statusMenuItem = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        toggleMenuItem = NSMenuItem(
            title: coordinator.isRunning ? "Остановить" : "Запустить",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        checkNowMenuItem = NSMenuItem(title: "Проверить сейчас", action: #selector(checkNow), keyEquivalent: "")
        checkNowMenuItem.target = self
        menu.addItem(checkNowMenuItem)

        menu.addItem(.separator())

        intervalMenuItem = NSMenuItem(title: intervalText(), action: nil, keyEquivalent: "")
        intervalMenuItem.submenu = buildIntervalMenu()
        menu.addItem(intervalMenuItem)

        let commandPreview = settings.commandText.count > 48
            ? String(settings.commandText.prefix(48)) + "…"
            : settings.commandText
        let commandItem = NSMenuItem(title: "Команда: \(commandPreview)", action: nil, keyEquivalent: "")
        commandItem.isEnabled = false
        menu.addItem(commandItem)

        menu.addItem(.separator())

        let openBrowser = NSMenuItem(
            title: "Открыть браузер ChatPulse…",
            action: #selector(showBrowser),
            keyEquivalent: "b"
        )
        openBrowser.target = self
        menu.addItem(openBrowser)

        let addCurrent = NSMenuItem(
            title: "Добавить текущий чат браузера",
            action: #selector(addCurrentChat),
            keyEquivalent: ""
        )
        addCurrent.target = self
        menu.addItem(addCurrent)

        chatsMenuItem = NSMenuItem(title: "Чаты (\(settings.chats.count))", action: nil, keyEquivalent: "")
        menu.addItem(chatsMenuItem)
        rebuildChatsSubmenu()

        menu.addItem(.separator())

        let browserInfo = NSMenuItem(
            title: "Как работает встроенный браузер…",
            action: #selector(showBrowserInfo),
            keyEquivalent: ""
        )
        browserInfo.target = self
        menu.addItem(browserInfo)

        let showLog = NSMenuItem(title: "Последние действия…", action: #selector(showRecentLog), keyEquivalent: "")
        showLog.target = self
        menu.addItem(showLog)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти из ChatPulse", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func refreshDynamicMenuItems() {
        statusMenuItem.title = statusText()
        toggleMenuItem.title = coordinator.isRunning ? "Остановить" : "Запустить"
        checkNowMenuItem.isEnabled = true
        intervalMenuItem.title = intervalText()

        let symbol = coordinator.isRunning ? "waveform.path.ecg" : "waveform.path.ecg.rectangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ChatPulse")
        statusItem.button?.image?.isTemplate = true
    }

    private func buildIntervalMenu() -> NSMenu {
        let submenu = NSMenu()
        let presets: [(String, TimeInterval)] = [
            ("1 минута", 60),
            ("2 минуты", 120),
            ("5 минут", 300),
            ("10 минут", 600),
            ("15 минут", 900),
            ("30 минут", 1_800)
        ]

        for (title, value) in presets {
            let item = NSMenuItem(title: title, action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: value)
            item.state = abs(settings.checkIntervalSeconds - value) < 0.5 ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let custom = NSMenuItem(title: "Свой интервал…", action: #selector(setCustomInterval), keyEquivalent: "")
        custom.target = self
        submenu.addItem(custom)
        return submenu
    }

    private func rebuildChatsSubmenu() {
        guard chatsMenuItem != nil else { return }
        chatsMenuItem.title = "Чаты (\(settings.chats.count))"
        let submenu = NSMenu()

        if settings.chats.isEmpty {
            let empty = NSMenuItem(title: "Нет добавленных чатов", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for chat in settings.chats {
                let parent = NSMenuItem(title: chat.title, action: nil, keyEquivalent: "")
                let chatMenu = NSMenu()

                let enabled = NSMenuItem(title: "Отслеживать", action: #selector(toggleChat(_:)), keyEquivalent: "")
                enabled.target = self
                enabled.representedObject = chat.id.uuidString
                enabled.state = chat.isEnabled ? .on : .off
                chatMenu.addItem(enabled)

                let open = NSMenuItem(
                    title: "Открыть во встроенном браузере",
                    action: #selector(openChat(_:)),
                    keyEquivalent: ""
                )
                open.target = self
                open.representedObject = chat.id.uuidString
                chatMenu.addItem(open)

                chatMenu.addItem(.separator())
                let remove = NSMenuItem(title: "Удалить из ChatPulse", action: #selector(removeChat(_:)), keyEquivalent: "")
                remove.target = self
                remove.representedObject = chat.id.uuidString
                chatMenu.addItem(remove)

                parent.submenu = chatMenu
                submenu.addItem(parent)
            }
        }

        chatsMenuItem.submenu = submenu
    }

    @objc private func toggleMonitoring() {
        coordinator.isRunning ? coordinator.stop() : coordinator.start()
        refreshDynamicMenuItems()
    }

    @objc private func checkNow() {
        coordinator.checkNow()
    }

    @objc private func showBrowser() {
        browser.showBrowser()
    }

    @objc private func addCurrentChat() {
        addCurrentChatFromBrowser()
    }

    private func addCurrentChatFromBrowser() {
        do {
            let captured = try browser.captureCurrentChat()
            if let existing = settings.chats.firstIndex(where: { $0.url == captured.url }) {
                settings.chats[existing].title = captured.title
                settings.chats[existing].isEnabled = true
                showAlert(title: "Чат уже добавлен", message: "Название обновлено: \(captured.title)")
            } else {
                settings.chats.append(MonitoredChat(title: captured.title, url: captured.url))
                showAlert(title: "Чат добавлен", message: captured.title)
            }
            persistSettings()
            rebuildChatsSubmenu()
        } catch {
            showAlert(title: "Не удалось добавить чат", message: error.localizedDescription)
        }
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        updateInterval(number.doubleValue)
    }

    @objc private func setCustomInterval() {
        let alert = NSAlert()
        alert.messageText = "Интервал проверки"
        alert.informativeText = "Введите количество минут (минимум 0,5)."
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")

        let field = NSTextField(string: String(format: "%.1f", settings.checkIntervalSeconds / 60))
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn,
              let minutes = Double(field.stringValue.replacingOccurrences(of: ",", with: ".")) else {
            return
        }
        updateInterval(minutes * 60)
    }

    private func updateInterval(_ seconds: TimeInterval) {
        settings.checkIntervalSeconds = AppSettings.clampedInterval(seconds)
        persistSettings()
        intervalMenuItem.submenu = buildIntervalMenu()
        refreshDynamicMenuItems()
        coordinator.reschedule()
    }

    @objc private func toggleChat(_ sender: NSMenuItem) {
        guard let id = representedChatID(sender),
              let index = settings.chats.firstIndex(where: { $0.id == id }) else { return }
        settings.chats[index].isEnabled.toggle()
        persistSettings()
        rebuildChatsSubmenu()
    }

    @objc private func openChat(_ sender: NSMenuItem) {
        guard let chat = representedChat(sender) else { return }
        browser.open(chat: chat)
    }

    @objc private func removeChat(_ sender: NSMenuItem) {
        guard let chat = representedChat(sender) else { return }
        let alert = NSAlert()
        alert.messageText = "Удалить чат?"
        alert.informativeText = chat.title
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        settings.chats.removeAll { $0.id == chat.id }
        persistSettings()
        rebuildChatsSubmenu()
    }

    @objc private func showBrowserInfo() {
        showAlert(
            title: "Встроенный браузер ChatPulse",
            message: "Браузер работает на системном движке WebKit — той же технологии, что используется Safari. Вход в ChatGPT выполняется один раз внутри ChatPulse и сохраняется отдельно от Safari. Фоновая проверка идёт в скрытом WebKit-окне и не переключает открытую страницу."
        )
    }

    @objc private func showRecentLog() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entries = log.snapshot().suffix(25)
        let text = entries.isEmpty
            ? "Действий пока нет."
            : entries.map { "[\(formatter.string(from: $0.date))] \($0.level.rawValue)  \($0.message)" }
                .joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Последние действия"
        alert.informativeText = text
        alert.addButton(withTitle: "Закрыть")
        alert.runModal()
    }

    @objc private func quitApplication() {
        coordinator.stop()
        NSApp.terminate(nil)
    }

    private func representedChatID(_ sender: NSMenuItem) -> UUID? {
        guard let raw = sender.representedObject as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private func representedChat(_ sender: NSMenuItem) -> MonitoredChat? {
        guard let id = representedChatID(sender) else { return nil }
        return settings.chats.first { $0.id == id }
    }

    private func persistSettings() {
        do {
            try store.save(settings)
        } catch {
            showAlert(title: "Не удалось сохранить настройки", message: error.localizedDescription)
        }
    }

    private func statusText() -> String {
        switch monitorStatus.state {
        case .stopped:
            return "Статус: остановлен"
        case .idle:
            if let next = monitorStatus.nextCheckAt {
                return "Статус: работает · следующая проверка \(timeFormatter.string(from: next))"
            }
            return "Статус: работает"
        case .checking:
            return "Статус: проверка чатов…"
        case .sent(let title):
            return "Отправлено: \(title)"
        case .warning(let message):
            return "Внимание: \(message)"
        }
    }

    private func intervalText() -> String {
        let minutes = settings.checkIntervalSeconds / 60
        if minutes.rounded() == minutes {
            return "Интервал: \(Int(minutes)) мин"
        }
        return "Интервал: \(String(format: "%.1f", minutes)) мин"
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "ОК")
        alert.runModal()
    }
}
#endif
