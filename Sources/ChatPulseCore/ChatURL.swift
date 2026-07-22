import Foundation

public enum ChatURL {
    private static let supportedHosts: Set<String> = ["chatgpt.com", "chat.openai.com"]

    public static func normalized(_ rawValue: String) -> String? {
        guard var components = URLComponents(string: rawValue),
              let host = components.host?.lowercased(),
              supportedHosts.contains(host) else {
            return nil
        }

        let pathComponents = components.path.split(separator: "/")
        guard pathComponents.indices.contains(where: { index in
            pathComponents[index] == "c" && pathComponents.indices.contains(index + 1)
        }) else {
            return nil
        }

        components.scheme = "https"
        components.host = "chatgpt.com"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    public static func isSupported(_ rawValue: String) -> Bool {
        normalized(rawValue) != nil
    }
}
