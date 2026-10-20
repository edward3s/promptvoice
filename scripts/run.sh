#!/bin/bash
# Compila y abre PromptVoice. Uso: ./scripts/run.sh [--install]
#   --install  copia la app a /Applications y la abre desde ahí.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build-mac/Build/Products/Debug/PromptVoice.app"
./scripts/build.sh

if [ "${1:-}" = "--install" ]; then
  pkill -x PromptVoice 2>/dev/null || true
  rm -rf "/Applications/PromptVoice.app"
  cp -R "$APP" "/Applications/PromptVoice.app"
  open "/Applications/PromptVoice.app"
else
  pkill -x PromptVoice 2>/dev/null || true
  open "$APP"
fi
