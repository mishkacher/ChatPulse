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
    webkit = read("Sources/ChatPulseApp/WebKitBrowserController.swift")
    browser_window = read("Sources/ChatPulseApp/BrowserWindowController.swift")
    app = read("Sources/ChatPulseApp/AppDelegate.swift")
    coordinator = read("Sources/ChatPulseApp/MonitorCoordinator.swift")
    store = read("Sources/ChatPulseCore/SettingsStore.swift")
    package = read("Package.swift")
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
        ("11 защита от повтора", "lastCommandedFingerprint" in engine),
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
        ("18 встроенный WebKit без Chrome", "WKWebView" in webkit + browser_window and "Google Chrome" not in webkit + app),
        ("19 CI проверяет тесты и сборку", "swift test" in workflow and "build_app.sh" in workflow),
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
