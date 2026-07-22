#if canImport(AppKit)
import AppKit
import WebKit

@MainActor
final class BrowserWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onAddCurrentChat: (() -> Void)?

    private let addressField = NSTextField(labelWithString: "chatgpt.com")

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
            contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Браузер ChatPulse"
        window.minSize = NSSize(width: 720, height: 520)
        window.center()

        super.init(window: window)

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
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        updateNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        updateNavigationState()
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

        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            decisionHandler(.allow)
        } else {
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
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
#endif
