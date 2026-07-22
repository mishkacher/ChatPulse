#if canImport(AppKit)
import AppKit
import QuartzCore
import WebKit
import ChatPulseCore

/// Управляет визуальной оболочкой ChatPulse и хранит выбранный скин отдельно
/// от рабочих настроек мониторинга. Это исключает гонки между сменой темы и
/// фоновым сохранением чатов.
@MainActor
final class SkinCoordinator: NSObject {
    static let shared = SkinCoordinator()

    private enum Constants {
        static let defaultsKey = "ChatPulse.ui.skin"
        static let selectorIdentifier = NSUserInterfaceItemIdentifier("chatpulse.skin.selector")
        static let toolbarGradientName = "ChatPulsePreviewToolbarGradient"
        static let buttonGradientName = "ChatPulsePreviewButtonGradient"

        // Точные цвета из docs/chatpulse-overview.svg.
        static let previewBackgroundStart = NSColor(chatPulseHex: "#071126")
        static let previewBackgroundMiddle = NSColor(chatPulseHex: "#11183A")
        static let previewBackgroundEnd = NSColor(chatPulseHex: "#24123D")
        static let previewAccentStart = NSColor(chatPulseHex: "#2C8CFF")
        static let previewAccentEnd = NSColor(chatPulseHex: "#9B5CFF")
        static let previewPrimaryText = NSColor(chatPulseHex: "#FFFFFF")
        static let previewSecondaryText = NSColor(chatPulseHex: "#AAB4D2")
        static let previewControlBackground = NSColor(chatPulseHex: "#222638")
        static let previewControlBorder = NSColor(chatPulseHex: "#4E5874")
    }

    private(set) var activeSkin: AppSkin
    private var observerTokens: [NSObjectProtocol] = []
    private var started = false

    private override init() {
        let stored = UserDefaults.standard.string(forKey: Constants.defaultsKey)
        activeSkin = stored.flatMap(AppSkin.init(rawValue:)) ?? .macOS
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        observerTokens.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in self?.apply(to: window) }
        })
        observerTokens.append(center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in self?.apply(to: window) }
        })

        applyToAllWindows()
    }

    func select(_ skin: AppSkin) {
        guard skin != activeSkin else {
            refreshSelectors()
            return
        }
        activeSkin = skin
        UserDefaults.standard.set(skin.rawValue, forKey: Constants.defaultsKey)
        applyToAllWindows()
    }

    private func applyToAllWindows() {
        for window in NSApp.windows where isChatPulseWindow(window) {
            apply(to: window)
        }
        refreshSelectors()
    }

    private func isChatPulseWindow(_ window: NSWindow) -> Bool {
        guard let contentView = window.contentView else { return false }
        return containsWebView(in: contentView)
            || window.title.localizedCaseInsensitiveContains("ChatPulse")
    }

    private func containsWebView(in view: NSView) -> Bool {
        if view is WKWebView { return true }
        return view.subviews.contains(where: containsWebView(in:))
    }

    private func apply(to window: NSWindow) {
        guard isChatPulseWindow(window) else { return }

        installSkinSelectorIfNeeded(in: window)

        switch activeSkin {
        case .macOS:
            applyMacOSSkin(to: window)
        case .chatPulsePreview:
            applyPreviewSkin(to: window)
        }
        updateSelector(in: window)
    }

    private func browserToolbar(in window: NSWindow) -> NSView? {
        guard let contentView = window.contentView else { return nil }
        return contentView.subviews.first { view in
            !(view is WKWebView) && containsWebView(in: contentView)
        }
    }

    private func installSkinSelectorIfNeeded(in window: NSWindow) {
        guard let toolbar = browserToolbar(in: window),
              toolbar.viewWithIdentifier(Constants.selectorIdentifier) == nil else {
            return
        }

        let selector = NSPopUpButton(frame: .zero, pullsDown: false)
        selector.identifier = Constants.selectorIdentifier
        selector.toolTip = "Выбрать скин интерфейса ChatPulse"
        selector.translatesAutoresizingMaskIntoConstraints = false
        selector.target = self
        selector.action = #selector(skinSelectionChanged(_:))

        for skin in AppSkin.allCases {
            selector.addItem(withTitle: skin.displayName)
            selector.lastItem?.representedObject = skin.rawValue
        }

        toolbar.addSubview(selector)

        if let statusField = findLoginStatusField(in: toolbar) {
            for constraint in toolbar.constraints where
                (constraint.firstItem as AnyObject?) === statusField
                    && constraint.firstAttribute == .trailing {
                constraint.priority = .defaultHigh
            }
            for constraint in toolbar.constraints where
                (constraint.secondItem as AnyObject?) === statusField
                    && constraint.secondAttribute == .trailing {
                constraint.priority = .defaultHigh
            }

            NSLayoutConstraint.activate([
                statusField.trailingAnchor.constraint(
                    lessThanOrEqualTo: selector.leadingAnchor,
                    constant: -8
                )
            ])
        }

        NSLayoutConstraint.activate([
            selector.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            selector.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -4),
            selector.widthAnchor.constraint(equalToConstant: 174),
            selector.heightAnchor.constraint(equalToConstant: 25)
        ])
    }

    private func findLoginStatusField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.stringValue.hasPrefix("Вход:") {
            return field
        }
        for subview in view.subviews {
            if let found = findLoginStatusField(in: subview) { return found }
        }
        return nil
    }

    @objc private func skinSelectionChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let skin = AppSkin(rawValue: rawValue) else {
            return
        }
        select(skin)
    }

    private func refreshSelectors() {
        for window in NSApp.windows {
            updateSelector(in: window)
        }
    }

    private func updateSelector(in window: NSWindow) {
        guard let selector = window.contentView?
            .viewWithIdentifier(Constants.selectorIdentifier) as? NSPopUpButton else {
            return
        }
        if let index = selector.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == activeSkin.rawValue
        }) {
            selector.selectItem(at: index)
        }
        selector.toolTip = "Скин: \(activeSkin.displayName)"
    }

    private func applyMacOSSkin(to window: NSWindow) {
        window.appearance = nil
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor

        guard let toolbar = browserToolbar(in: window) else { return }
        toolbar.wantsLayer = true
        removeLayer(named: Constants.toolbarGradientName, from: toolbar.layer)
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        styleTextFields(in: toolbar, primary: .labelColor, secondary: .secondaryLabelColor)
        styleButtons(in: toolbar, skin: .macOS)
    }

    private func applyPreviewSkin(to window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Constants.previewBackgroundStart

        guard let toolbar = browserToolbar(in: window) else { return }
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = Constants.previewBackgroundStart.cgColor
        installGradient(
            named: Constants.toolbarGradientName,
            colors: [
                Constants.previewBackgroundStart,
                Constants.previewBackgroundMiddle,
                Constants.previewBackgroundEnd
            ],
            in: toolbar.layer,
            frame: toolbar.bounds,
            cornerRadius: 0
        )

        styleTextFields(
            in: toolbar,
            primary: Constants.previewPrimaryText,
            secondary: Constants.previewSecondaryText
        )
        styleButtons(in: toolbar, skin: .chatPulsePreview)
    }

    private func styleTextFields(in view: NSView, primary: NSColor, secondary: NSColor) {
        for subview in view.subviews {
            if let field = subview as? NSTextField {
                field.textColor = field.stringValue.hasPrefix("Вход:") ? secondary : primary
            }
            styleTextFields(in: subview, primary: primary, secondary: secondary)
        }
    }

    private func styleButtons(in view: NSView, skin: AppSkin) {
        for subview in view.subviews {
            if let popUp = subview as? NSPopUpButton {
                stylePopUp(popUp, skin: skin)
            } else if let button = subview as? NSButton {
                styleButton(button, skin: skin)
            }
            styleButtons(in: subview, skin: skin)
        }
    }

    private func styleButton(_ button: NSButton, skin: AppSkin) {
        button.wantsLayer = true
        removeLayer(named: Constants.buttonGradientName, from: button.layer)

        switch skin {
        case .macOS:
            button.isBordered = true
            button.bezelStyle = button.image == nil ? .rounded : .texturedRounded
            button.contentTintColor = nil
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.borderWidth = 0
            button.layer?.cornerRadius = 0
            restoreButtonTitle(button, color: .labelColor)

        case .chatPulsePreview:
            button.isBordered = false
            button.contentTintColor = Constants.previewPrimaryText
            button.layer?.cornerRadius = 9
            button.layer?.masksToBounds = true

            let isPrimary = button.title == "Добавить чат"
            if isPrimary {
                installGradient(
                    named: Constants.buttonGradientName,
                    colors: [Constants.previewAccentStart, Constants.previewAccentEnd],
                    in: button.layer,
                    frame: button.bounds,
                    cornerRadius: 9
                )
                button.layer?.borderWidth = 0
            } else {
                button.layer?.backgroundColor = Constants.previewControlBackground.cgColor
                button.layer?.borderColor = Constants.previewControlBorder.cgColor
                button.layer?.borderWidth = 1
            }
            restoreButtonTitle(button, color: Constants.previewPrimaryText)
        }
    }

    private func stylePopUp(_ popUp: NSPopUpButton, skin: AppSkin) {
        popUp.wantsLayer = true
        removeLayer(named: Constants.buttonGradientName, from: popUp.layer)

        switch skin {
        case .macOS:
            popUp.isBordered = true
            popUp.bezelStyle = .rounded
            popUp.contentTintColor = nil
            popUp.layer?.backgroundColor = NSColor.clear.cgColor
            popUp.layer?.borderWidth = 0
            popUp.layer?.cornerRadius = 0
        case .chatPulsePreview:
            popUp.isBordered = false
            popUp.contentTintColor = Constants.previewPrimaryText
            popUp.layer?.backgroundColor = Constants.previewControlBackground.cgColor
            popUp.layer?.borderColor = Constants.previewControlBorder.cgColor
            popUp.layer?.borderWidth = 1
            popUp.layer?.cornerRadius = 8
            popUp.layer?.masksToBounds = true
        }
    }

    private func restoreButtonTitle(_ button: NSButton, color: NSColor) {
        guard !button.title.isEmpty else { return }
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            ]
        )
    }

    private func installGradient(
        named name: String,
        colors: [NSColor],
        in parentLayer: CALayer?,
        frame: NSRect,
        cornerRadius: CGFloat
    ) {
        guard let parentLayer else { return }
        removeLayer(named: name, from: parentLayer)

        let gradient = CAGradientLayer()
        gradient.name = name
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.frame = frame
        gradient.cornerRadius = cornerRadius
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        parentLayer.insertSublayer(gradient, at: 0)
    }

    private func removeLayer(named name: String, from layer: CALayer?) {
        layer?.sublayers?.filter { $0.name == name }.forEach { $0.removeFromSuperlayer() }
    }
}

private extension NSColor {
    convenience init(chatPulseHex value: String) {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let parsed = UInt64(cleaned, radix: 16) ?? 0
        let red = CGFloat((parsed >> 16) & 0xFF) / 255
        let green = CGFloat((parsed >> 8) & 0xFF) / 255
        let blue = CGFloat(parsed & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
#endif
