#if canImport(AppKit)
import AppKit
import ChatPulseCore

/// Добавляет выбор скина прямо в меню значка ChatPulse в строке состояния.
///
/// Меню строки состояния создаётся `AppDelegate`, поэтому установщик
/// подключается к стандартному уведомлению AppKit о начале отслеживания меню.
/// Он изменяет только меню, которое однозначно распознано как меню ChatPulse.
@MainActor
final class SkinStatusMenuInstaller: NSObject {
    static let shared = SkinStatusMenuInstaller()

    private let parentIdentifier = NSUserInterfaceItemIdentifier("chatpulse.status.skin")
    private var observer: NSObjectProtocol?

    private override init() {
        super.init()
    }

    func start() {
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let menu = notification.object as? NSMenu else { return }
            Task { @MainActor in
                self?.installOrRefresh(in: menu)
            }
        }
    }

    private func installOrRefresh(in menu: NSMenu) {
        guard isChatPulseStatusMenu(menu) else { return }

        let parent: NSMenuItem
        if let existing = menu.items.first(where: { $0.identifier == parentIdentifier }) {
            parent = existing
        } else {
            parent = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            parent.identifier = parentIdentifier

            let insertionIndex = menu.items.firstIndex(where: {
                $0.title == "Открыть браузер ChatPulse…"
            }) ?? menu.items.count
            menu.insertItem(parent, at: insertionIndex)
        }

        parent.title = "Скин: \(SkinCoordinator.shared.activeSkin.displayName)"
        parent.submenu = buildSkinSubmenu()
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
               $0.identifier == parentIdentifier
           }) {
            statusParent.title = "Скин: \(skin.displayName)"
            statusParent.submenu = buildSkinSubmenu()
        }
    }
}
#endif
