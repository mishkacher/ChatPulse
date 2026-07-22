#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT_DIR/scripts/build_app.sh"

SOURCE_APP="$ROOT_DIR/dist/ChatPulse.app"
DESTINATION="/Applications/ChatPulse.app"

rm -rf "$DESTINATION"
cp -R "$SOURCE_APP" "$DESTINATION"
open "$DESTINATION"

echo "Установлено: $DESTINATION"
