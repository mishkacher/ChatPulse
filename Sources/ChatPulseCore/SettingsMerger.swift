import Foundation

/// Объединяет служебное состояние, полученное во время проверки чатов,
/// с самой свежей пользовательской конфигурацией.
///
/// Проверка WebKit может длиться десятки секунд и приостанавливаться на `await`.
/// За это время пользователь способен изменить интервал, отключить или удалить чат.
/// Поэтому нельзя сохранять старый снимок настроек целиком: это отменит действия пользователя.
public enum SettingsMerger {
    public static func mergeRuntimeState(
        from observedSettings: AppSettings,
        into latestSettings: AppSettings
    ) -> AppSettings {
        var merged = latestSettings
        let observedByID = Dictionary(
            uniqueKeysWithValues: observedSettings.chats.map { ($0.id, $0) }
        )

        for index in merged.chats.indices {
            guard let observed = observedByID[merged.chats[index].id] else {
                continue
            }

            merged.chats[index].lastObservedFingerprint = observed.lastObservedFingerprint
            merged.chats[index].lastCommandedFingerprint = observed.lastCommandedFingerprint
            merged.chats[index].lastObservedAt = observed.lastObservedAt
            merged.chats[index].lastCommandAt = observed.lastCommandAt
        }

        return merged
    }
}
