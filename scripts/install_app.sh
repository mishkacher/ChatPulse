#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/scripts/build_app.sh"

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
