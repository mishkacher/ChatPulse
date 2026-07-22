#if canImport(AppKit)
import AppKit
import Foundation
import WebKit
import ChatPulseCore

@MainActor
protocol BrowserControlling: AnyObject {
    func captureCurrentChat() throws -> (title: String, url: String)
    func inspect(chat: MonitoredChat) async throws -> BrowserSnapshot
    func send(command: String, to chat: MonitoredChat) async throws -> CommandSendOutcome
    func open(chat: MonitoredChat)
    func showBrowser()
}

enum WebKitBrowserError: LocalizedError {
    case browserNotOpen
    case unsupportedPage
    case invalidURL
    case pageLoadTimedOut
    case malformedResponse(String)
    case scriptFailure(String)
    case sendUnavailable
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .browserNotOpen:
            return "Сначала откройте встроенный браузер ChatPulse и войдите в ChatGPT."
        case .unsupportedPage:
            return "Во встроенном браузере открыт не конкретный чат ChatGPT."
        case .invalidURL:
            return "Адрес сохранённого чата повреждён или больше не поддерживается."
        case .pageLoadTimedOut:
            return "Страница ChatGPT не загрузилась за отведённое время."
        case .malformedResponse(let value):
            return "Встроенный браузер вернул неожиданный ответ: \(value.prefix(160))"
        case .scriptFailure(let message):
            return "Ошибка встроенного браузера: \(message)"
        case .sendUnavailable:
            return "Кнопка отправки сейчас недоступна. ChatPulse повторит попытку при следующей проверке."
        case .sendFailed(let message):
            return "Не удалось отправить команду: \(message)"
        }
    }
}

@MainActor
final class WebKitBrowserController: NSObject, BrowserControlling {
    var onAddCurrentChat: (() -> Void)? {
        didSet { browserWindowController.onAddCurrentChat = onAddCurrentChat }
    }

    private let decoder = JSONDecoder()
    private let dataStore: WKWebsiteDataStore
    private let monitorWebView: WKWebView
    private let browserWindowController: BrowserWindowController
    private var navigationWaiter: NavigationWaiter?

    override init() {
        dataStore = .default()

        let monitorConfiguration = WKWebViewConfiguration()
        monitorConfiguration.websiteDataStore = dataStore
        monitorConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
        monitorWebView = WKWebView(frame: .zero, configuration: monitorConfiguration)
        browserWindowController = BrowserWindowController(dataStore: dataStore)

        super.init()
    }

    func showBrowser() {
        browserWindowController.show()
    }

    func captureCurrentChat() throws -> (title: String, url: String) {
        guard let currentURL = browserWindowController.currentURL else {
            throw WebKitBrowserError.browserNotOpen
        }
        guard let normalized = ChatURL.normalized(currentURL.absoluteString) else {
            throw WebKitBrowserError.unsupportedPage
        }
        return (browserWindowController.currentTitle, normalized)
    }

    func open(chat: MonitoredChat) {
        guard let normalized = ChatURL.normalized(chat.url), let url = URL(string: normalized) else {
            browserWindowController.show()
            return
        }
        browserWindowController.show(initialURL: url)
    }

    func inspect(chat: MonitoredChat) async throws -> BrowserSnapshot {
        try await loadChat(chat)

        var lastRaw = ""
        for attempt in 0..<30 {
            lastRaw = try await evaluateString(Self.inspectJavaScript, in: monitorWebView)
            if let snapshot = decodeSnapshot(lastRaw), snapshot.latestFingerprint != nil || snapshot.errorDetected {
                return snapshot
            }
            if attempt < 29 {
                try await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        guard let snapshot = decodeSnapshot(lastRaw) else {
            throw WebKitBrowserError.malformedResponse(lastRaw)
        }
        return snapshot
    }

    /// Отправляет команду и возвращает результат после фактического клика.
    ///
    /// Ошибки до клика безопасно повторяются на следующей проверке. После клика метод
    /// никогда не просит повторять команду: если DOM-подтверждение не появилось вовремя,
    /// возвращается `.submittedUnconfirmed`, чтобы сохранить at-most-once семантику.
    func send(command: String, to chat: MonitoredChat) async throws -> CommandSendOutcome {
        if ChatURL.normalized(monitorWebView.url?.absoluteString ?? "") != ChatURL.normalized(chat.url) {
            try await loadChat(chat)
        }

        let commandJSON = try jsonStringLiteral(command)
        let fillScript = Self.fillJavaScript.replacingOccurrences(of: "__COMMAND_JSON__", with: commandJSON)
        let fillResult = try await evaluateString(fillScript, in: monitorWebView)
        guard fillResult == "filled" else {
            throw WebKitBrowserError.sendFailed(fillResult)
        }

        var clicked = false
        for _ in 0..<30 {
            let result = try await evaluateString(Self.clickSendJavaScript, in: monitorWebView)
            if result == "clicked" {
                clicked = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard clicked else {
            throw WebKitBrowserError.sendUnavailable
        }

        let confirmationScript = Self.confirmSendJavaScript
            .replacingOccurrences(of: "__COMMAND_JSON__", with: commandJSON)
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let result = try await evaluateString(confirmationScript, in: monitorWebView)
            if result == "confirmed" {
                return .confirmed
            }
        }

        return .submittedUnconfirmed
    }

    private func loadChat(_ chat: MonitoredChat) async throws {
        guard let normalized = ChatURL.normalized(chat.url), let url = URL(string: normalized) else {
            throw WebKitBrowserError.invalidURL
        }

        let request = URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 30
        )
        let waiter = NavigationWaiter()
        navigationWaiter = waiter
        monitorWebView.navigationDelegate = waiter
        defer { navigationWaiter = nil }
        try await waiter.load(request, in: monitorWebView)
    }

    private func decodeSnapshot(_ raw: String) -> BrowserSnapshot? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? decoder.decode(BrowserSnapshot.self, from: data)
    }

    private func evaluateString(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: WebKitBrowserError.scriptFailure(error.localizedDescription))
                    return
                }
                guard let value = result as? String else {
                    continuation.resume(throwing: WebKitBrowserError.malformedResponse(String(describing: result)))
                    return
                }
                continuation.resume(returning: value)
            }
        }
    }

    private func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let result = String(data: data, encoding: .utf8) else {
            throw WebKitBrowserError.sendFailed("не удалось подготовить текст команды")
        }
        return result
    }

    private static let inspectJavaScript = #"""
    (()=>{const hash=(s)=>{let h=2166136261;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619);}return(h>>>0).toString(16)};const messages=[...document.querySelectorAll('[data-message-author-role]')];const last=messages.at(-1)||null;const role=(last?.getAttribute('data-message-author-role')||'unknown').toLowerCase();const text=(last?.innerText||last?.textContent||'').replace(/\s+/g,' ').trim();const mid=last?.getAttribute('data-message-id')||last?.id||'';const fp=last?hash(role+'|'+mid+'|'+text):null;const buttons=[...document.querySelectorAll('button')];const generating=!!document.querySelector('button[data-testid="stop-button"]')||buttons.some(b=>/^(stop|остановить)/i.test((b.getAttribute('aria-label')||b.innerText||'').trim()));const alerts=[...document.querySelectorAll('[role="alert"],[aria-live="assertive"],[data-testid*="error" i]')].map(e=>(e.innerText||e.textContent||'').toLowerCase()).join('\n');const error=/(something went wrong|network error|failed to load|произошла ошибка|ошибка сети|не удалось загрузить)/i.test(alerts);let title=(document.title||'Чат ChatGPT').replace(/\s*[-|]\s*ChatGPT\s*$/i,'').trim();return JSON.stringify({title:title,url:location.href,latestRole:['assistant','user','system'].includes(role)?role:'unknown',latestFingerprint:fp,isGenerating:generating,errorDetected:error,pageReady:document.readyState==='complete'||document.readyState==='interactive'});})()
    """#

    private static let fillJavaScript = #"""
    (()=>{if(document.querySelector('button[data-testid="stop-button"]'))return'generating';const command=__COMMAND_JSON__;const input=document.querySelector('#prompt-textarea')||document.querySelector('textarea')||document.querySelector('[contenteditable="true"]');if(!input)return'no-input';input.focus();if(input instanceof HTMLTextAreaElement||input instanceof HTMLInputElement){const proto=input instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const setter=Object.getOwnPropertyDescriptor(proto,'value')?.set;setter?.call(input,command);input.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:command}));}else{input.innerHTML='';const p=document.createElement('p');p.textContent=command;input.appendChild(p);input.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:command}));}return'filled';})()
    """#

    private static let clickSendJavaScript = #"""
    (()=>{const buttons=[...document.querySelectorAll('button')];const send=document.querySelector('button[data-testid="send-button"]')||buttons.find(b=>/^(send|отправить)/i.test((b.getAttribute('aria-label')||b.innerText||'').trim()));if(!send||send.disabled)return'unavailable';send.click();return'clicked';})()
    """#

    private static let confirmSendJavaScript = #"""
    (()=>{const command=__COMMAND_JSON__.replace(/\s+/g,' ').trim();const messages=[...document.querySelectorAll('[data-message-author-role]')];const last=messages.at(-1)||null;const role=(last?.getAttribute('data-message-author-role')||'').toLowerCase();const text=(last?.innerText||last?.textContent||'').replace(/\s+/g,' ').trim();return role==='user'&&text===command?'confirmed':'not-confirmed';})()
    """#
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    func load(_ request: URLRequest, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(request)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(WebKitBrowserError.pageLoadTimedOut))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
#endif
