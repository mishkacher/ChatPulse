#if canImport(AppKit)
import AppKit
import Foundation
import ChatPulseCore

protocol BrowserControlling: Sendable {
    func captureCurrentChat() throws -> (title: String, url: String)
    func inspect(chat: MonitoredChat) throws -> BrowserSnapshot
    func send(command: String, to chat: MonitoredChat) throws
    func open(chat: MonitoredChat) throws
}

enum ChromeAutomationError: LocalizedError {
    case chromeUnavailable
    case unsupportedPage
    case javascriptEventsDisabled
    case malformedResponse(String)
    case scriptFailure(String)
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .chromeUnavailable:
            return "Google Chrome не запущен или недоступен."
        case .unsupportedPage:
            return "Откройте нужный чат ChatGPT в Google Chrome."
        case .javascriptEventsDisabled:
            return "В Chrome отключено «Allow JavaScript from Apple Events». Включите его в View → Developer."
        case .malformedResponse(let value):
            return "Chrome вернул неожиданный ответ: \(value.prefix(160))"
        case .scriptFailure(let message):
            return "Ошибка управления Chrome: \(message)"
        case .sendFailed(let message):
            return "Не удалось отправить команду: \(message)"
        }
    }
}

final class ChromeAutomation: BrowserControlling, @unchecked Sendable {
    private let decoder = JSONDecoder()

    func captureCurrentChat() throws -> (title: String, url: String) {
        let javascript = Self.captureJavaScript
        let source = """
        tell application "Google Chrome"
            if not running then return "__ERROR__:CHROME_NOT_RUNNING"
            if (count of windows) is 0 then return "__ERROR__:NO_WINDOWS"
            set targetTab to active tab of front window
            return execute targetTab javascript "\(Self.appleScriptEscaped(javascript))"
        end tell
        """

        let raw = try runAppleScript(source)
        try validateRawResponse(raw)

        struct Capture: Decodable {
            let title: String
            let url: String
            let supported: Bool
        }

        guard let data = raw.data(using: .utf8),
              let capture = try? decoder.decode(Capture.self, from: data) else {
            throw ChromeAutomationError.malformedResponse(raw)
        }

        guard capture.supported, let normalized = ChatURL.normalized(capture.url) else {
            throw ChromeAutomationError.unsupportedPage
        }

        let cleanedTitle = capture.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanedTitle.isEmpty ? "ChatGPT chat" : cleanedTitle, normalized)
    }

    func inspect(chat: MonitoredChat) throws -> BrowserSnapshot {
        let raw = try executeInChat(chatURL: chat.url, javascript: Self.inspectJavaScript)
        try validateRawResponse(raw)

        guard let data = raw.data(using: .utf8),
              let snapshot = try? decoder.decode(BrowserSnapshot.self, from: data) else {
            throw ChromeAutomationError.malformedResponse(raw)
        }
        return snapshot
    }

    func send(command: String, to chat: MonitoredChat) throws {
        let commandJSON = try jsonStringLiteral(command)
        let javascript = Self.sendJavaScript.replacingOccurrences(of: "__COMMAND_JSON__", with: commandJSON)
        let raw = try executeInChat(chatURL: chat.url, javascript: javascript)
        try validateRawResponse(raw)

        guard raw == "scheduled" else {
            throw ChromeAutomationError.sendFailed(raw)
        }

        Thread.sleep(forTimeInterval: 3.2)
        let confirmationJavaScript = Self.confirmSendJavaScript
            .replacingOccurrences(of: "__COMMAND_JSON__", with: commandJSON)
        let confirmation = try executeInChat(chatURL: chat.url, javascript: confirmationJavaScript)
        try validateRawResponse(confirmation)
        guard confirmation == "confirmed" else {
            throw ChromeAutomationError.sendFailed("Chrome не подтвердил появление сообщения в чате.")
        }
    }

    func open(chat: MonitoredChat) throws {
        let source = Self.locateTabAppleScript(
            chatURL: chat.url,
            body: "set active tab index of targetWindow to targetIndex\nset index of targetWindow to 1\nactivate\nreturn \"opened\""
        )
        let raw = try runAppleScript(source)
        try validateRawResponse(raw)
    }

    private func executeInChat(chatURL: String, javascript: String) throws -> String {
        let body = "return execute targetTab javascript \"\(Self.appleScriptEscaped(javascript))\""
        let source = Self.locateTabAppleScript(chatURL: chatURL, body: body)
        return try runAppleScript(source)
    }

    private func runAppleScript(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw ChromeAutomationError.scriptFailure("Не удалось создать AppleScript.")
        }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? error.description
            if message.localizedCaseInsensitiveContains("javascript from apple events") {
                throw ChromeAutomationError.javascriptEventsDisabled
            }
            throw ChromeAutomationError.scriptFailure(message)
        }
        return descriptor.stringValue ?? ""
    }

    private func validateRawResponse(_ raw: String) throws {
        if raw == "__ERROR__:CHROME_NOT_RUNNING" || raw == "__ERROR__:NO_WINDOWS" {
            throw ChromeAutomationError.chromeUnavailable
        }
        if raw.hasPrefix("__ERROR__:") {
            throw ChromeAutomationError.scriptFailure(raw)
        }
    }

    private func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let result = String(data: data, encoding: .utf8) else {
            throw ChromeAutomationError.sendFailed("Не удалось подготовить текст команды.")
        }
        return result
    }

    private static func locateTabAppleScript(chatURL: String, body: String) -> String {
        let escapedURL = appleScriptEscaped(chatURL)
        return """
        tell application "Google Chrome"
            if not running then launch
            delay 0.3
            if (count of windows) is 0 then make new window
            set targetURL to "\(escapedURL)"
            set targetTab to missing value
            set targetWindow to missing value
            set targetIndex to 1
            repeat with currentWindow in windows
                set tabCounter to 0
                repeat with currentTab in tabs of currentWindow
                    set tabCounter to tabCounter + 1
                    set currentURL to URL of currentTab as text
                    if currentURL starts with targetURL then
                        set targetTab to currentTab
                        set targetWindow to currentWindow
                        set targetIndex to tabCounter
                        exit repeat
                    end if
                end repeat
                if targetTab is not missing value then exit repeat
            end repeat
            if targetTab is missing value then
                set targetWindow to front window
                set targetTab to make new tab at end of tabs of targetWindow with properties {URL:targetURL}
                set targetIndex to count of tabs of targetWindow
            end if
            repeat with attempt from 1 to 30
                try
                    set readyState to execute targetTab javascript "document.readyState"
                    if readyState is "complete" or readyState is "interactive" then exit repeat
                end try
                delay 0.2
            end repeat
            \(body)
        end tell
        """
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static let captureJavaScript = #"""
    (()=>{const u=location.href;const ok=/^https:\/\/(chatgpt\.com|chat\.openai\.com)\/c\//.test(u);let t=document.title||'ChatGPT chat';t=t.replace(/\s*[-|]\s*ChatGPT\s*$/i,'').trim();return JSON.stringify({title:t,url:u,supported:ok});})()
    """#

    private static let inspectJavaScript = #"""
    (()=>{const hash=(s)=>{let h=2166136261;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619);}return(h>>>0).toString(16)};const messages=[...document.querySelectorAll('[data-message-author-role]')];const last=messages.at(-1)||null;const role=(last?.getAttribute('data-message-author-role')||'unknown').toLowerCase();const text=(last?.innerText||last?.textContent||'').trim();const mid=last?.getAttribute('data-message-id')||last?.id||'';const fp=last?hash(role+'|'+mid+'|'+text):null;const buttons=[...document.querySelectorAll('button')];const generating=!!document.querySelector('button[data-testid="stop-button"]')||buttons.some(b=>/^(stop|остановить)/i.test((b.getAttribute('aria-label')||b.innerText||'').trim()));const alerts=[...document.querySelectorAll('[role="alert"],[aria-live="assertive"],[data-testid*="limit" i],[data-testid*="error" i]')].map(e=>(e.innerText||e.textContent||'').toLowerCase()).join('\n');const limit=/(usage limit|rate limit|message limit|try again after|достигнут.*лимит|лимит.*сообщ|попробуйте снова.*через|техническ.*лимит достигнут)/i.test(alerts);const error=/(something went wrong|network error|failed to load|произошла ошибка|ошибка сети|не удалось загрузить)/i.test(alerts);let title=(document.title||'ChatGPT chat').replace(/\s*[-|]\s*ChatGPT\s*$/i,'').trim();return JSON.stringify({title:title,url:location.href,latestRole:['assistant','user','system'].includes(role)?role:'unknown',latestFingerprint:fp,isGenerating:generating,limitDetected:limit,errorDetected:error,pageReady:document.readyState==='complete'||document.readyState==='interactive'});})()
    """#

    private static let confirmSendJavaScript = #"""
    (()=>{const command=__COMMAND_JSON__.replace(/\s+/g,' ').trim();const messages=[...document.querySelectorAll('[data-message-author-role]')];const last=messages.at(-1)||null;const role=(last?.getAttribute('data-message-author-role')||'').toLowerCase();const text=(last?.innerText||last?.textContent||'').replace(/\s+/g,' ').trim();return role==='user'&&text===command?'confirmed':'not-confirmed';})()
    """#

    private static let sendJavaScript = #"""
    (()=>{if(document.querySelector('button[data-testid="stop-button"]'))return'generating';const command=__COMMAND_JSON__;const input=document.querySelector('#prompt-textarea')||document.querySelector('textarea')||document.querySelector('[contenteditable="true"]');if(!input)return'no-input';input.focus();if(input instanceof HTMLTextAreaElement||input instanceof HTMLInputElement){const proto=input instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const setter=Object.getOwnPropertyDescriptor(proto,'value')?.set;setter?.call(input,command);input.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:command}));}else{input.innerHTML='';const p=document.createElement('p');p.textContent=command;input.appendChild(p);input.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:command}));}let tries=0;const timer=setInterval(()=>{tries++;const send=document.querySelector('button[data-testid="send-button"]')||[...document.querySelectorAll('button')].find(b=>/^(send|отправить)/i.test((b.getAttribute('aria-label')||b.innerText||'').trim()));if(send&&!send.disabled){clearInterval(timer);send.click();}else if(tries>=30){clearInterval(timer);const form=input.closest('form');if(form?.requestSubmit)form.requestSubmit();}},100);return'scheduled';})()
    """#
}
#endif
