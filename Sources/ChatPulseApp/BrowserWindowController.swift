#if canImport(AppKit)
import AppKit
import WebKit
import ChatPulseCore

@MainActor
final class BrowserWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let webView: WKWebView
    var onAddCurrentChat: (() -> Void)?

    private let addressField = NSTextField(labelWithString: "chatgpt.com")
    private let loginStatusField = NSTextField(labelWithString: "Вход: выберите email / код или passkey")
    private var popupWindows: [ObjectIdentifier: NSWindow] = [:]
    private var isShowingGoogleSignInAlert = false
    private var pendingLoginMethod: ChatPulseLoginMethod?
    private var preparedLoginPages = Set<String>()

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

    private lazy var loginButton: NSButton = {
        let button = NSButton(title: "Войти ▾", target: self, action: #selector(showLoginMenu))
        button.bezelStyle = .rounded
        button.toolTip = "Выбрать способ входа в ChatGPT"
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
        window.minSize = NSSize(width: 760, height: 540)
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

        loginStatusField.translatesAutoresizingMaskIntoConstraints = false
        loginStatusField.lineBreakMode = .byTruncatingTail
        loginStatusField.maximumNumberOfLines = 1
        loginStatusField.textColor = .secondaryLabelColor
        loginStatusField.font = NSFont.systemFont(ofSize: 11)

        let controls = NSStackView(views: [backButton, forwardButton, reloadButton, homeButton])
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.translatesAutoresizingMaskIntoConstraints = false

        loginButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(controls)
        toolbar.addSubview(addressField)
        toolbar.addSubview(loginButton)
        toolbar.addSubview(addButton)
        toolbar.addSubview(loginStatusField)
        contentView.addSubview(toolbar)
        contentView.addSubview(webView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 72),

            controls.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            controls.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10),

            addButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            addButton.centerYAnchor.constraint(equalTo: controls.centerYAnchor),

            loginButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),
            loginButton.centerYAnchor.constraint(equalTo: controls.centerYAnchor),

            addressField.leadingAnchor.constraint(equalTo: controls.trailingAnchor, constant: 12),
            addressField.trailingAnchor.constraint(equalTo: loginButton.leadingAnchor, constant: -12),
            addressField.centerYAnchor.constraint(equalTo: controls.centerYAnchor),

            loginStatusField.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            loginStatusField.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            loginStatusField.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -8),

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
        pendingLoginMethod = nil
        preparedLoginPages.removeAll()
        setLoginStatus("Открыта главная страница ChatGPT")
        load(URL(string: "https://chatgpt.com/")!)
    }

    @objc private func addCurrentChat() {
        onAddCurrentChat?()
    }

    @objc private func showLoginMenu() {
        let menu = NSMenu()

        let emailItem = NSMenuItem(
            title: "Войти по email / коду",
            action: #selector(beginEmailCodeLogin),
            keyEquivalent: ""
        )
        emailItem.target = self
        menu.addItem(emailItem)

        let passkeyItem = NSMenuItem(
            title: "Войти с passkey",
            action: #selector(beginPasskeyLogin),
            keyEquivalent: ""
        )
        passkeyItem.target = self
        menu.addItem(passkeyItem)

        menu.addItem(.separator())

        let codeItem = NSMenuItem(
            title: "Запросить код по email на этой странице",
            action: #selector(requestEmailCodeOnCurrentPage),
            keyEquivalent: ""
        )
        codeItem.target = self
        menu.addItem(codeItem)

        let helpItem = NSMenuItem(
            title: "Как работают эти способы…",
            action: #selector(showLoginHelp),
            keyEquivalent: ""
        )
        helpItem.target = self
        menu.addItem(helpItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: loginButton.bounds.height + 4),
            in: loginButton
        )
    }

    @objc private func beginEmailCodeLogin() {
        startLogin(.emailCode)
    }

    @objc private func beginPasskeyLogin() {
        startLogin(.passkey)
    }

    @objc private func requestEmailCodeOnCurrentPage() {
        setLoginStatus("Ищу кнопку запроса кода по email…")
        evaluateLoginScript(LoginSupport.requestEmailCodeJavaScript, in: webView) { [weak self] result in
            guard let self else { return }
            switch result {
            case "email-code-requested":
                self.setLoginStatus("Запрос кода отправлен. Используйте самое новое письмо OpenAI")
            case "script-error":
                self.setLoginStatus("Не удалось выполнить действие на странице")
            default:
                self.setLoginStatus("Кнопка запроса кода не найдена на текущем шаге")
                self.showEmailCodeNotFoundAlert()
            }
        }
    }

    @objc private func showLoginHelp() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Вход по email-коду и passkey"
        alert.informativeText = "Email / код: ChatPulse открывает официальный экран OpenAI и фокусирует поле email. Сам код приходит от OpenAI и вводится только на странице входа.\n\nPasskey: WebKit передаёт запрос системному окну macOS, где используется Touch ID, пароль Mac, iCloud Keychain или совместимый ключ безопасности. Passkey должен быть заранее добавлен в аккаунт OpenAI.\n\nЕсли аккаунт был создан только через Google, OpenAI может не разрешить перейти на email-вход. Тогда сначала добавьте passkey в настройках безопасности ChatGPT, войдя в обычном Safari или приложении ChatGPT."
        alert.addButton(withTitle: "Понятно")
        alert.runModal()
    }

    private func startLogin(_ method: ChatPulseLoginMethod) {
        pendingLoginMethod = method
        preparedLoginPages.removeAll()

        switch method {
        case .emailCode:
            setLoginStatus("Открываю официальный вход OpenAI по email / коду…")
        case .passkey:
            setLoginStatus("Открываю вход OpenAI и проверяю доступность passkey…")
        }

        load(LoginSupport.loginURL)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func preparePendingLogin(in targetWebView: WKWebView) {
        guard let method = pendingLoginMethod,
              let url = targetWebView.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return
        }

        let pageKey = "\(method.rawValue)|\(url.absoluteString)"
        guard preparedLoginPages.insert(pageKey).inserted else { return }

        switch method {
        case .emailCode:
            evaluateLoginScript(LoginSupport.emailCodePreparationJavaScript, in: targetWebView) { [weak self] result in
                guard let self else { return }
                switch result {
                case "email-focused":
                    self.setLoginStatus("Введите email. Если OpenAI запросит проверку, введите код из письма")
                case "email-choice-clicked":
                    self.setLoginStatus("Выбран вход по email. Дождитесь появления поля адреса")
                    self.scheduleLoginPreparationRetry(in: targetWebView)
                case "script-error":
                    self.setLoginStatus("Не удалось подготовить страницу входа по email")
                default:
                    self.setLoginStatus("Продолжите вход вручную: выберите email и используйте код из письма")
                }
            }
        case .passkey:
            evaluateLoginScript(LoginSupport.passkeyPreparationJavaScript, in: targetWebView) { [weak self] result in
                guard let self else { return }
                switch result {
                case "passkey-triggered":
                    self.setLoginStatus("Подтвердите passkey в системном окне macOS")
                case "passkey-available-no-button":
                    self.setLoginStatus("Passkey доступен. Введите email, затем выберите вход с ключом доступа")
                case "passkey-unavailable":
                    self.setLoginStatus("На этом Mac не найден доступный passkey для текущего шага")
                    self.showPasskeyUnavailableAlert()
                case "passkey-unsupported":
                    self.setLoginStatus("Текущая страница не предложила WebAuthn / passkey")
                    self.showPasskeyUnavailableAlert()
                case "script-error":
                    self.setLoginStatus("Не удалось проверить passkey на странице")
                default:
                    self.setLoginStatus("Введите email; OpenAI покажет passkey, если он привязан к аккаунту")
                }
            }
        }
    }

    private func scheduleLoginPreparationRetry(in targetWebView: WKWebView) {
        Task { @MainActor [weak self, weak targetWebView] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, let targetWebView else { return }
            self.preparedLoginPages.removeAll()
            self.preparePendingLogin(in: targetWebView)
        }
    }

    private func detectCompletedLogin(in targetWebView: WKWebView) {
        guard targetWebView === webView,
              LoginSupport.isLikelySuccessfulLoginURL(targetWebView.url) else {
            return
        }

        evaluateLoginScript(LoginSupport.authenticatedStateJavaScript, in: targetWebView) { [weak self] result in
            guard let self, result == "authenticated" else { return }
            self.pendingLoginMethod = nil
            self.preparedLoginPages.removeAll()
            self.setLoginStatus("Вход выполнен. Откройте чат и нажмите «Добавить чат»")
        }
    }

    private func evaluateLoginScript(
        _ script: String,
        in targetWebView: WKWebView,
        completion: @escaping @MainActor (String) -> Void
    ) {
        targetWebView.evaluateJavaScript(script) { result, error in
            let value = result as? String
            let hasError = error != nil
            Task { @MainActor in
                completion(hasError ? "script-error" : (value ?? "unknown"))
            }
        }
    }

    private func setLoginStatus(_ message: String) {
        loginStatusField.stringValue = "Вход: \(message)"
        loginStatusField.toolTip = message
    }

    private func showEmailCodeNotFoundAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Запрос кода сейчас недоступен"
        alert.informativeText = "Сначала выберите «Войти по email / коду» и введите email. Кнопка «Попробовать с email» появляется только на тех шагах, где OpenAI предлагает альтернативную проверку."
        alert.addButton(withTitle: "Открыть вход по email")
        alert.addButton(withTitle: "Отмена")
        if alert.runModal() == .alertFirstButtonReturn {
            beginEmailCodeLogin()
        }
    }

    private func showPasskeyUnavailableAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Passkey пока не найден"
        alert.informativeText = "Passkey должен быть заранее добавлен в аккаунт OpenAI и доступен в iCloud Keychain, менеджере паролей или на совместимом ключе безопасности. Иногда OpenAI показывает вариант passkey только после ввода email."
        alert.addButton(withTitle: "Открыть вход и ввести email")
        alert.addButton(withTitle: "Отмена")
        if alert.runModal() == .alertFirstButtonReturn {
            pendingLoginMethod = .passkey
            preparedLoginPages.removeAll()
            load(LoginSupport.loginURL)
        }
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

        detectCompletedLogin(in: webView)
        preparePendingLogin(in: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        if webView === self.webView {
            updateNavigationState()
            setLoginStatus("Ошибка загрузки: \(error.localizedDescription)")
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if webView === self.webView {
            updateNavigationState()
            setLoginStatus("Ошибка загрузки: \(error.localizedDescription)")
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
        alert.informativeText = "Google запрещает OAuth-авторизацию во встроенных WebView. Выберите вход по email / коду или passkey. Если аккаунт был создан только через Google, сначала добавьте passkey в настройках безопасности OpenAI через обычный Safari или приложение ChatGPT."
        alert.addButton(withTitle: "Email / код")
        alert.addButton(withTitle: "Passkey")
        alert.addButton(withTitle: "Отмена")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            beginEmailCodeLogin()
        case .alertSecondButtonReturn:
            beginPasskeyLogin()
        default:
            break
        }
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
