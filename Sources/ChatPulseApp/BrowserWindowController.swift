#if canImport(AppKit)
import AppKit
import WebKit
import ChatPulseCore

@MainActor
final class BrowserWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    var onAddCurrentChat: (() -> Void)?

    private let addressField = NSTextField(labelWithString: "chatgpt.com")
    private var popupWindows: [ObjectIdentifier: NSWindow] = [:]
    private var isShowingGoogleSignInAlert = false

    private lazy var backButton: NSButton = {
        let button = NSButton(
            image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Назад") ?? NSImage(),
            target: self,
            action: #selector(goBack)
        )
        button.bezelStyle = .texturedRounded
        button.toolTip = "Назад"
        return button
    }()

    private lazy var forwardButton: NSButton = {
        let button = NSButton(
            image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Вперёд") ?? NSImage(),
            target: self,
            action: #selector(goForward)
        )
        button.bezelStyle = .texturedRounded
        button.toolTip = "Вперёд"
        return button
    }()

    private lazy var reloadButton: NSButton = {
        let button = NSButton(
            image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Обновить") ?? NSImage(),
            target: self,
            action: #selector(reloadPage)
        )
        button.bezelStyle = .texturedRounded
        button.toolTip = "Обновить"
        return button
    }()

    private lazy var homeButton: NSButton = {
        let button = NSButton(
            image: NSImage(systemSymbolName: "house", accessibilityDescription: "ChatGPT") ?? NSImage(),
            target: self,
            action: #selector(openHome)
        )
        button.bezelStyle = .texturedRounded
        button.toolTip = "Открыть ChatGPT"
        return button
    }()

    private lazy var addButton: NSButton = {
        let button = NSButton(title: "Добавить чат", target: self, action: #selector(addCurrentChat))
        button.bezelStyle = .rounded
        button.toolTip = "Добавить открытый чат в ChatPulse"
        return button
    }()

    init(dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)

        let window = NSWindow(
            contentRect: Self.constrainedFrame(preferredSize: NSSize(width: 1_080, height: 760)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Браузер ChatPulse"
        window.minSize = NSSize(width: 720, height: 520)
        window.maxSize = Self.maximumWindowSize(on: NSScreen.main)
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        configureInterface()
        updateNavigationState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) не поддерживается")
    }

    var currentURL: URL? { webView.url }

    var currentTitle: String {
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Чат ChatGPT" : title.replacingOccurrences(
            of: #"\s*[-|]\s*ChatGPT\s*$"#,
            with: "",
            options: .regularExpression
        )
    }

    func show(initialURL: URL? = nil) {
        constrainToVisibleScreen(window)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let initialURL {
            load(initialURL)
        } else if webView.url == nil {
            load(URL(string: "https://chatgpt.com/")!)
        }
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    private func configureInterface() {
        guard let contentView = window?.contentView else { return }

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.maximumNumberOfLines = 1
        addressField.textColor = .secondaryLabelColor
        addressField.alignment = .center

        let controls = NSStackView(views: [backButton, forwardButton, reloadButton, homeButton])
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.translatesAutoresizingMaskIntoConstraints = false

        addButton.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(controls)
        toolbar.addSubview(addressField)
        toolbar.addSubview(addButton)
        contentView.addSubview(toolbar)
        contentView.addSubview(webView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 46),

            controls.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            controls.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            addButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            addButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            addressField.leadingAnchor.constraint(equalTo: controls.trailingAnchor, constant: 12),
            addressField.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -12),
            addressField.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func updateNavigationState() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        addressField.stringValue = webView.url?.absoluteString ?? "chatgpt.com"
        window?.title = currentTitle == "Чат ChatGPT" ? "Браузер ChatPulse" : "\(currentTitle) — ChatPulse"
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    @objc private func reloadPage() {
        webView.reload()
    }

    @objc private func openHome() {
        load(URL(string: "https://chatgpt.com/")!)
    }

    @objc private func addCurrentChat() {
        onAddCurrentChat?()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView {
            updateNavigationState()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView {
            updateNavigationState()
        } else if let popupWindow = popupWindows[ObjectIdentifier(webView)] {
            let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            popupWindow.title = title.isEmpty ? "Вход — ChatPulse" : title
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        if webView === self.webView {
            updateNavigationState()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if webView === self.webView {
            updateNavigationState()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if AuthenticationURL.isGoogleSignIn(url) {
            decisionHandler(.cancel)
            closePopup(for: webView)
            showGoogleSignInUnavailableAlert()
            return
        }

        switch url.scheme?.lowercased() {
        case "http", "https", "about":
            decisionHandler(.allow)
        default:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        if let url = navigationAction.request.url, AuthenticationURL.isGoogleSignIn(url) {
            showGoogleSignInUnavailableAlert()
            return nil
        }

        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self
        popupWebView.autoresizingMask = [.width, .height]

        let screen = window?.screen ?? NSScreen.main
        let popupWindow = NSWindow(
            contentRect: Self.constrainedFrame(
                preferredSize: NSSize(width: 720, height: 760),
                on: screen
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        popupWindow.title = "Вход — ChatPulse"
        popupWindow.minSize = NSSize(width: 520, height: 480)
        popupWindow.maxSize = Self.maximumWindowSize(on: screen)
        popupWindow.isReleasedWhenClosed = false
        popupWindow.delegate = self
        popupWindow.contentView = popupWebView

        popupWindows[ObjectIdentifier(popupWebView)] = popupWindow
        constrainToVisibleScreen(popupWindow)
        popupWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        closePopup(for: webView)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow !== window else {
            return
        }

        if let popupWebView = closingWindow.contentView as? WKWebView {
            popupWindows.removeValue(forKey: ObjectIdentifier(popupWebView))
        }
    }

    private func closePopup(for webView: WKWebView) {
        guard webView !== self.webView,
              let popupWindow = popupWindows.removeValue(forKey: ObjectIdentifier(webView)) else {
            return
        }
        popupWindow.orderOut(nil)
        popupWindow.close()
    }

    private func showGoogleSignInUnavailableAlert() {
        guard !isShowingGoogleSignInAlert else { return }
        isShowingGoogleSignInAlert = true
        defer { isShowingGoogleSignInAlert = false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Вход через Google недоступен во встроенном браузере"
        alert.informativeText = "Google запрещает OAuth-авторизацию во встроенных WebView. ChatPulse остановил переход, поэтому огромное белое окно больше не откроется. Вернитесь на страницу входа ChatGPT и выберите другой доступный способ авторизации. Сессия Safari не может быть перенесена во встроенный браузер ChatPulse."
        alert.addButton(withTitle: "Понятно")
        alert.runModal()
    }

    private func constrainToVisibleScreen(_ window: NSWindow?) {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.main
        window.maxSize = Self.maximumWindowSize(on: screen)
        window.setFrame(
            Self.constrainedFrame(preferredSize: window.frame.size, on: screen),
            display: true
        )
    }

    private static func maximumWindowSize(on screen: NSScreen?) -> NSSize {
        let visibleFrame = safeVisibleFrame(on: screen)
        return NSSize(width: visibleFrame.width, height: visibleFrame.height)
    }

    private static func constrainedFrame(
        preferredSize: NSSize,
        on screen: NSScreen? = NSScreen.main
    ) -> NSRect {
        let visibleFrame = safeVisibleFrame(on: screen)
        let width = min(max(preferredSize.width, 520), visibleFrame.width)
        let height = min(max(preferredSize.height, 480), visibleFrame.height)

        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func safeVisibleFrame(on screen: NSScreen?) -> NSRect {
        let fallback = NSRect(x: 0, y: 0, width: 1_280, height: 800)
        let frame = (screen ?? NSScreen.main)?.visibleFrame ?? fallback
        let inset = frame.insetBy(dx: 20, dy: 20)
        return inset.width >= 520 && inset.height >= 480 ? inset : frame
    }
}
#endif
