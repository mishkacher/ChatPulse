#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_app.sh"

if [[ ! -f "$BUILD_SCRIPT" ]]; then
  echo "Не найден сборочный скрипт: $BUILD_SCRIPT" >&2
  exit 1
fi

# Запускаем через bash, поэтому установка не зависит от executable-бита,
# с которым файл был получен из ZIP или GitHub.
bash "$BUILD_SCRIPT"

SOURCE_APP="$ROOT_DIR/dist/ChatPulse.app"
SYSTEM_APPLICATIONS="/Applications"
USER_APPLICATIONS="$HOME/Applications"

if [[ -d "$SYSTEM_APPLICATIONS" && -w "$SYSTEM_APPLICATIONS" ]]; then
  DESTINATION="$SYSTEM_APPLICATIONS/ChatPulse.app"
else
  mkdir -p "$USER_APPLICATIONS"
  DESTINATION="$USER_APPLICATIONS/ChatPulse.app"
  echo "Нет прав записи в /Applications — используется $USER_APPLICATIONS"
fi

# Не заменяем файлы запущенного приложения.
pkill -x ChatPulse 2>/dev/null || true
sleep 0.3

rm -rf "$DESTINATION"
ditto "$SOURCE_APP" "$DESTINATION"
open "$DESTINATION"

echo "Установлено: $DESTINATION"