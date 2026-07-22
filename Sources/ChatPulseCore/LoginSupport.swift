import Foundation

public enum ChatPulseLoginMethod: String, Sendable {
    case emailCode
    case passkey
}

/// Небольшой слой, который подготавливает официальный экран входа ChatGPT.
///
/// ChatPulse не получает и не хранит email, одноразовые коды или passkey.
/// Ввод и системная авторизация происходят непосредственно на странице OpenAI
/// внутри `WKWebView`.
public enum LoginSupport {
    public static let loginURL = URL(string: "https://chatgpt.com/auth/login")!

    public static let emailCodePreparationJavaScript = #"""
    (() => {
      const normalize = value => (value || '').replace(/\s+/g, ' ').trim().toLowerCase();
      const emailInput = document.querySelector(
        'input[type="email"], input[name="email"], input[autocomplete="email"], input[autocomplete="username"]'
      );

      if (emailInput) {
        emailInput.scrollIntoView({ block: 'center' });
        emailInput.focus();
        return 'email-focused';
      }

      const controls = [...document.querySelectorAll('button, a, [role="button"]')];
      const emailChoice = controls.find(element => {
        const text = normalize(element.innerText || element.textContent || element.getAttribute('aria-label'));
        return /continue with email|use email|email address|электронн.*почт|войти.*почт/.test(text);
      });

      if (emailChoice) {
        emailChoice.click();
        return 'email-choice-clicked';
      }

      return 'email-control-not-found';
    })()
    """#

    public static let requestEmailCodeJavaScript = #"""
    (() => {
      const normalize = value => (value || '').replace(/\s+/g, ' ').trim().toLowerCase();
      const controls = [...document.querySelectorAll('button, a, [role="button"]')];
      const emailFallback = controls.find(element => {
        const text = normalize(element.innerText || element.textContent || element.getAttribute('aria-label'));
        return /try with email|use email|send.*email|email.*code|попробовать.*почт|код.*почт|отправить.*почт/.test(text);
      });

      if (!emailFallback) return 'email-code-control-not-found';
      emailFallback.click();
      return 'email-code-requested';
    })()
    """#

    public static let passkeyPreparationJavaScript = #"""
    (async () => {
      if (!window.PublicKeyCredential) return 'passkey-unsupported';

      let platformAvailable = false;
      let conditionalAvailable = false;
      try {
        platformAvailable = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
      } catch (_) {}
      try {
        if (PublicKeyCredential.isConditionalMediationAvailable) {
          conditionalAvailable = await PublicKeyCredential.isConditionalMediationAvailable();
        }
      } catch (_) {}

      const normalize = value => (value || '').replace(/\s+/g, ' ').trim().toLowerCase();
      const controls = [...document.querySelectorAll('button, a, [role="button"]')];
      const passkeyControl = controls.find(element => {
        const text = normalize(element.innerText || element.textContent || element.getAttribute('aria-label'));
        return /passkey|security key|ключ доступа|ключ безопасности/.test(text);
      });

      if (passkeyControl) {
        passkeyControl.click();
        return 'passkey-triggered';
      }

      if (platformAvailable || conditionalAvailable) return 'passkey-available-no-button';
      return 'passkey-unavailable';
    })()
    """#

    public static let authenticatedStateJavaScript = #"""
    (() => {
      const hasPrompt = Boolean(
        document.querySelector('#prompt-textarea') ||
        document.querySelector('textarea[placeholder]') ||
        document.querySelector('[contenteditable="true"][data-virtualkeyboard]')
      );
      const hasConversationUI = Boolean(
        document.querySelector('[data-testid="profile-button"]') ||
        document.querySelector('nav a[href^="/c/"]') ||
        document.querySelector('a[href^="/c/"]')
      );
      return hasPrompt || hasConversationUI ? 'authenticated' : 'not-authenticated';
    })()
    """#

    public static func isLikelySuccessfulLoginURL(_ url: URL?) -> Bool {
        guard let url,
              let host = url.host?.lowercased(),
              host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") else {
            return false
        }

        let path = url.path.lowercased()
        return !path.hasPrefix("/auth/") && path != "/auth" && !path.contains("login")
    }
}
