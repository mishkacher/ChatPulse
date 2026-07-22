#!/usr/bin/env bash
set -euo pipefail

pkill -x ChatPulse 2>/dev/null || true
rm -rf "/Applications/ChatPulse.app" "$HOME/Applications/ChatPulse.app"

echo "Приложение удалено."
echo "Настройки сохранены в ~/Library/Application Support/ChatPulse/."
