#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Релизный preflight ChatPulse выполняется только на macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_NUMBER_FILE="$ROOT_DIR/BUILD_NUMBER"
APP_DIR="$ROOT_DIR/dist/ChatPulse.app"
PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/ChatPulse"
ICON="$APP_DIR/Contents/Resources/ChatPulse.icns"

read_trimmed() {
  tr -d '[:space:]' < "$1"
}

[[ -f "$VERSION_FILE" ]] || { echo "Отсутствует VERSION" >&2; exit 1; }
[[ -f "$BUILD_NUMBER_FILE" ]] || { echo "Отсутствует BUILD_NUMBER" >&2; exit 1; }

VERSION="$(read_trimmed "$VERSION_FILE")"
BUILD_NUMBER="$(read_trimmed "$BUILD_NUMBER_FILE")"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Некорректная версия: $VERSION" >&2
  exit 1
}
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
  echo "Некорректный номер сборки: $BUILD_NUMBER" >&2
  exit 1
}

cd "$ROOT_DIR"

echo "[1/8] Проверка shell-скриптов"
for script in scripts/*.sh; do
  bash -n "$script"
done

echo "[2/8] Модульные тесты debug"
swift test

echo "[3/8] Модульные тесты release"
swift test -c release

echo "[4/8] Quality gates"
python3 scripts/quality_gate.py

echo "[5/8] Сборка приложения"
bash scripts/build_app.sh

echo "[6/8] Проверка структуры bundle"
test -x "$EXECUTABLE"
test -f "$ICON"
plutil -lint "$PLIST"

echo "[7/8] Проверка метаданных и подписи"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
MENU_BAR_ONLY="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$PLIST")"

[[ "$ACTUAL_VERSION" == "$VERSION" ]] || {
  echo "Версия bundle $ACTUAL_VERSION не совпадает с VERSION $VERSION" >&2
  exit 1
}
[[ "$ACTUAL_BUILD" == "$BUILD_NUMBER" ]] || {
  echo "Номер bundle $ACTUAL_BUILD не совпадает с BUILD_NUMBER $BUILD_NUMBER" >&2
  exit 1
}
[[ "$ACTUAL_BUNDLE_ID" == "com.mishkacher.ChatPulse" ]] || {
  echo "Неожиданный bundle identifier: $ACTUAL_BUNDLE_ID" >&2
  exit 1
}
[[ "$MENU_BAR_ONLY" == "true" ]] || {
  echo "LSUIElement должен быть true" >&2
  exit 1
}

codesign --verify --deep --strict "$APP_DIR"
codesign -dvv "$APP_DIR" 2>&1 | grep -q 'Identifier=com.mishkacher.ChatPulse'
codesign -dvv "$APP_DIR" 2>&1 | grep -q 'runtime'

echo "[8/8] Проверка релизной документации"
grep -q "Текущая версия: \*\*$VERSION\*\*" README.md
if grep -q "Текущая версия: \*\*$VERSION alpha\*\*" README.md; then
  echo "README всё ещё помечает релиз как alpha" >&2
  exit 1
fi
grep -q "## \[$VERSION\]" CHANGELOG.md
grep -q "# ChatPulse $VERSION" RELEASE_NOTES.md
grep -q "продолжай и не останавливайся до технического лимита" Sources/ChatPulseCore/Models.swift

echo
echo "Релизный preflight успешно завершён: ChatPulse $VERSION (build $BUILD_NUMBER)"
