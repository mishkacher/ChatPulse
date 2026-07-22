import Foundation

/// Распознаёт переходы к Google OAuth, которые нельзя безопасно выполнять
/// во встроенном `WKWebView` под управлением приложения.
public enum AuthenticationURL {
    public static func isGoogleSignIn(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue) else { return false }
        return isGoogleSignIn(url)
    }

    public static func isGoogleSignIn(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            return false
        }

        if host == "accounts.google.com"
            || host.hasSuffix(".accounts.google.com")
            || host == "oauth2.googleapis.com" {
            return true
        }

        let isAuthenticationHost = host == "auth.openai.com"
            || host.hasSuffix(".auth.openai.com")
            || host == "auth0.openai.com"
            || host.hasSuffix(".auth0.openai.com")
            || host.hasSuffix(".auth0.com")

        guard isAuthenticationHost else { return false }

        let normalizedPath = components.path.lowercased()
        if normalizedPath.contains("google") {
            return true
        }

        let providerKeys = Set([
            "connection",
            "provider",
            "idp",
            "identity_provider",
            "strategy"
        ])

        return (components.queryItems ?? []).contains { item in
            let name = item.name.lowercased()
            let value = item.value?.lowercased() ?? ""
            return providerKeys.contains(name) && value.contains("google")
        }
    }
}
