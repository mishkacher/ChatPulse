import Foundation

/// Визуальный стиль нативной оболочки ChatPulse.
///
/// Скин влияет только на элементы приложения: окно, панель управления,
/// кнопки и строку состояния. Содержимое сайта ChatGPT не модифицируется.
public enum AppSkin: String, Codable, CaseIterable, Equatable, Sendable {
    /// Системные материалы и цвета macOS с автоматической поддержкой
    /// светлого и тёмного режима.
    case macOS

    /// Фирменная тема из SVG-превью README:
    /// тёмный сине-фиолетовый фон и яркий сине-фиолетовый акцент.
    case chatPulsePreview

    public var displayName: String {
        switch self {
        case .macOS:
            return "macOS"
        case .chatPulsePreview:
            return "ChatPulse Preview"
        }
    }
}
