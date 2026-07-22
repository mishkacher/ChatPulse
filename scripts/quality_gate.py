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
    checks: list[tuple[str, bool]] = []

    models = read("Sources/ChatPulseCore/Models.swift")
    engine = read("Sources/ChatPulseCore/DecisionEngine.swift")
    chrome = read("Sources/ChatPulseApp/ChromeAutomation.swift")
    app = read("Sources/ChatPulseApp/AppDelegate.swift")
    coordinator = read("Sources/ChatPulseApp/MonitorCoordinator.swift")
    store = read("Sources/ChatPulseCore/SettingsStore.swift")
    package = read("Package.swift")
    workflow = read(".github/workflows/ci.yml") if (ROOT / ".github/workflows/ci.yml").exists() else ""

    checks.extend(
        [
            ("01 exact continuation command", EXPECTED_COMMAND in models),
            ("02 native macOS target", ".macOS(.v13)" in package),
            ("03 menu-bar accessory mode", "setActivationPolicy(.accessory)" in app),
            ("04 single start-stop toggle", "toggleMonitoring" in app and '"Запустить"' in app and '"Остановить"' in app),
            ("05 configurable interval", "setCustomInterval" in app and "checkIntervalSeconds" in models),
            ("06 minimum interval guard", "min(max(value, 30)" in models),
            ("07 persistent chat titles", "title: String" in models and "JSONSettingsStore" in store),
            ("08 atomic settings write", ".atomic" in store),
            ("09 baseline after launch", "isFirstObservationThisRun" in engine),
            ("10 response-change cooldown", ".responseChanged" in engine),
            ("11 duplicate suppression", "lastCommandedFingerprint" in engine),
            ("12 waits for assistant", "latestRole == .assistant" in engine),
            ("13 generation detection", "stop-button" in chrome),
            ("14 technical limit detection", "limitDetected" in chrome),
            ("15 page-error detection", "errorDetected" in chrome),
            ("16 confirmed send", "confirmSendJavaScript" in chrome and '"confirmed"' in chrome),
            ("17 stop cancellation before send", "Send cancelled because monitoring stopped" in coordinator),
            ("18 Chrome-only automation", 'application "Google Chrome"' in chrome),
            ("19 CI validates tests and app build", "swift test" in workflow and "build_app.sh" in workflow),
            ("20 no external AI/API dependency", not re.search(r"OpenAI|Anthropic|Ollama|API_KEY", package, re.I)),
        ]
    )

    failed = [name for name, passed in checks if not passed]
    for name, passed in checks:
        print(f"[{'PASS' if passed else 'FAIL'}] {name}")

    print(f"\n{len(checks) - len(failed)}/{len(checks)} quality gates passed")
    if failed:
        print("Failed gates:", ", ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
