#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_COMMAND = "продолжай и не останавливайся до технического лимита"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> int:
    models = read("Sources/ChatPulseCore/Models.swift")
    engine = read("Sources/ChatPulseCore/DecisionEngine.swift")
    merger = read("Sources/ChatPulseCore/SettingsMerger.swift")
    authentication = read("Sources/ChatPulseCore/AuthenticationURL.swift")
    login_support = read("Sources/ChatPulseCore/LoginSupport.swift")
    app_skin = read("Sources/ChatPulseCore/AppSkin.swift")
    skin_coordinator = read("Sources/ChatPulseApp/SkinCoordinator.swift")
    webkit = read("Sources/ChatPulseApp/WebKitBrowserController.swift")
    browser_window = read("Sources/ChatPulseApp/BrowserWindowController.swift")
    app = read("Sources/ChatPulseApp/AppDelegate.swift")
    coordinator = read("Sources/ChatPulseApp/MonitorCoordinator.swift")
    store = read("Sources/ChatPulseCore/SettingsStore.swift")
    package = read("Package.swift")
    installer = read("scripts/install_app.sh")
    build_script = read("scripts/build_app.sh")
    readme = read("README.md")
    workflow = read(".github/workflows/ci.yml") if (ROOT / ".github/workflows/ci.yml").exists() else ""

    checks: list[tuple[str, bool]] = [
        ("01 точная команда продолжения", EXPECTED_COMMAND in models),
        ("02 нативная цель macOS", ".macOS(.v13)" in package),
        ("03 приложение только в строке меню", "setActivationPolicy(.accessory)" in app),
        ("04 единая кнопка запуска и остановки", "toggleMonitoring" in app and '"Запустить"' in app and '"Остановить"' in app),
        ("05 настраиваемый интервал", "setCustomInterval" in app and "checkIntervalSeconds" in models),
        ("06 безопасные границы интервала", "min(max(value, 30)" in models),
        ("07 сохранение названий чатов", "title: String" in models and "JSONSettingsStore" in store),
        ("08 атомарная запись настроек", ".atomic" in store),
        ("09 пассивная первая проверка", "isFirstObservationThisRun" in engine),
        ("10 ожидание после нового ответа", ".responseChanged" in engine),
        (
            "11 at-most-once защита от повтора",
            "lastCommandedFingerprint" in engine
            and "CommandSendOutcome" in models
            and "submittedUnconfirmed" in webkit
            and "recordDispatchedCommand" in coordinator,
        ),
        ("12 ожидание ответа ассистента", "latestRole == .assistant" in engine),
        ("13 определение продолжающейся генерации", "stop-button" in webkit),
        ("14 детектор технического лимита удалён", "limitDetected" not in models + engine + webkit and "technicalLimit" not in models + engine),
        ("15 обработка ошибок страницы", "errorDetected" in webkit),
        ("16 подтверждение фактической отправки", "confirmSendJavaScript" in webkit and '"confirmed"' in webkit),
        (
            "17 остановка и изменения пользователя защищены",
            "Отправка отменена: наблюдение остановлено" in coordinator
            and "liveSettings.chats.contains" in coordinator
            and "SettingsMerger.mergeRuntimeState" in coordinator
            and "lastObservedFingerprint" in merger,
        ),
        (
            "18 WebKit-вход: Google перехвачен, email-код и passkey реализованы",
            "popupWindows" in browser_window
            and "constrainedFrame" in browser_window
            and "AuthenticationURL.isGoogleSignIn" in browser_window
            and "accounts.google.com" in authentication
            and "beginEmailCodeLogin" in browser_window
            and "requestEmailCodeOnCurrentPage" in browser_window
            and "beginPasskeyLogin" in browser_window
            and "emailCodePreparationJavaScript" in login_support
            and "requestEmailCodeJavaScript" in login_support
            and "PublicKeyCredential" in login_support
            and "isUserVerifyingPlatformAuthenticatorAvailable" in login_support,
        ),
        (
            "19 два сохраняемых скина и пять независимых полных CI-циклов",
            "case macOS" in app_skin
            and "case chatPulsePreview" in app_skin
            and "UserDefaults.standard.set" in skin_coordinator
            and "ChatPulse.ui.skin" in skin_coordinator
            and all(color in skin_coordinator for color in [
                "#071126", "#11183A", "#24123D", "#2C8CFF", "#9B5CFF"
            ])
            and "NSAppearance(named: .darkAqua)" in skin_coordinator
            and "matrix:" in workflow
            and "round: [1, 2, 3, 4, 5]" in workflow
            and "swift test" in workflow
            and "build_app.sh" in workflow
            and 'bash "$BUILD_SCRIPT"' in installer
            and 'git clone --depth 1' in readme
            and "0.4.0" in build_script,
        ),
        ("20 нет внешнего ИИ или платного API", not re.search(r"Anthropic|Ollama|API_KEY", package, re.I)),
    ]

    failed = [name for name, passed in checks if not passed]
    for name, passed in checks:
        print(f"[{'PASS' if passed else 'FAIL'}] {name}")

    print(f"\n{len(checks) - len(failed)}/{len(checks)} проверок пройдено")
    if failed:
        print("Не пройдены:", ", ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
