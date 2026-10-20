#!/bin/bash
# Compila y abre Voice. Uso: ./scripts/run.sh [--install]
#   --install  copia la app a /Applications y la abre desde ahí.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build-mac/Build/Products/Debug/Voice.app"
./scripts/build.sh

if [ "${1:-}" = "--install" ]; then
  pkill -f "Voice.app/Contents/MacOS/Voice" 2>/dev/null || true
  rm -rf "/Applications/Voice.app"
  cp -R "$APP" "/Applications/Voice.app"
  open "/Applications/Voice.app"
else
  pkill -f "Voice.app/Contents/MacOS/Voice" 2>/dev/null || true
  open "$APP"
fi
