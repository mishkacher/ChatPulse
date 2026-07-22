#if canImport(AppKit)
import AppKit
import ChatPulseCore

/// Добавляет выбор скина и сведения о версии прямо в меню значка ChatPulse.
///
/// Меню строки состояния создаётся `AppDelegate`, поэтому установщик следит
/// за публичным уведомлением AppKit о добавлении пунктов. После завершения
/// построения меню он изменяет только однозначно распознанное меню ChatPulse.
@MainActor
final class SkinStatusMenuInstaller: NSObject {
    static let shared = SkinStatusMenuInstaller()

    private let skinIdentifier = NSUserInterfaceItemIdentifier("chatpulse.status.skin")
    private let aboutIdentifier = NSUserInterfaceItemIdentifier("chatpulse.status.about")
    private var isStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // Selector-based API вызывается синхронно на том потоке, где AppKit
        // изменяет меню. Все меню ChatPulse строятся на MainActor, поэтому здесь
        // нет передачи NSMenu/Notification между Sendable-замыканиями Swift 6.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
    }

    @objc private func menuDidAddItem(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        installOrRefresh(in: menu)
    }

    private func installOrRefresh(in menu: NSMenu) {
        guard isChatPulseStatusMenu(menu) else { return }
        installSkinItem(in: menu)
        installAboutItem(in: menu)
    }

    private func installSkinItem(in menu: NSMenu) {
        let parent: NSMenuItem
        if let existing = menu.items.first(where: { $0.identifier == skinIdentifier }) {
            parent = existing
        } else {
            parent = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            parent.identifier = skinIdentifier

            let insertionIndex = menu.items.firstIndex(where: {
                $0.title == "Открыть браузер ChatPulse…"
            }) ?? menu.items.count
            menu.insertItem(parent, at: insertionIndex)
        }

        parent.title = "Скин: \(SkinCoordinator.shared.activeSkin.displayName)"
        parent.submenu = buildSkinSubmenu()
    }

    private func installAboutItem(in menu: NSMenu) {
        guard menu.items.first(where: { $0.identifier == aboutIdentifier }) == nil else {
            return
        }

        let about = NSMenuItem(
            title: "О ChatPulse…",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.identifier = aboutIdentifier
        about.target = self

        let insertionIndex = menu.items.firstIndex(where: {
            $0.title == "Выйти из ChatPulse"
        }) ?? menu.items.count
        menu.insertItem(about, at: insertionIndex)
    }

    private func isChatPulseStatusMenu(_ menu: NSMenu) -> Bool {
        let titles = Set(menu.items.map(\.title))
        let hasStatus = menu.items.contains { $0.title.hasPrefix("Статус:") }
        return hasStatus
            && titles.contains("Открыть браузер ChatPulse…")
            && titles.contains("Выйти из ChatPulse")
    }

    private func buildSkinSubmenu() -> NSMenu {
        let submenu = NSMenu(title: "Скин интерфейса")

        for skin in AppSkin.allCases {
            let item = NSMenuItem(
                title: skin.displayName,
                action: #selector(selectSkin(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = skin.rawValue
            item.state = skin == SkinCoordinator.shared.activeSkin ? .on : .off
            submenu.addItem(item)
        }

        return submenu
    }

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let skin = AppSkin(rawValue: rawValue) else {
            return
        }

        SkinCoordinator.shared.select(skin)

        if let statusMenu = sender.menu?.supermenu,
           let statusParent = statusMenu.items.first(where: {
               $0.identifier == skinIdentifier
           }) {
            statusParent.title = "Скин: \(skin.displayName)"
            statusParent.submenu = buildSkinSubmenu()
        }
    }

    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "неизвестно"
        let build = info["CFBundleVersion"] as? String ?? "неизвестно"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "ChatPulse \(version)"
        alert.informativeText = "Build \(build)\n\nНативная утилита строки меню macOS для мониторинга выбранных разговоров ChatGPT. Настройки хранятся локально; телеметрия, внешний ИИ и платные API не используются.\n\nMIT License."
        alert.addButton(withTitle: "Понятно")
        alert.addButton(withTitle: "Открыть Releases")

        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "https://github.com/mishkacher/ChatPulse/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
