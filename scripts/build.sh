#!/bin/bash
# Compila la app de macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild \
  -project PromptVoice.xcodeproj \
  -scheme PromptVoice \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build-mac \
  build

echo "App: $(pwd)/build-mac/Build/Products/Debug/PromptVoice.app"
