#!/bin/bash
# Compila y ejecuta la app Tasks
set -e
cd "$(dirname "$0")/.."
xcodebuild -scheme Tasks -configuration Debug build -quiet
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Tasks.app" -path "*/Build/Products/Debug/*" 2>/dev/null | head -1)
if [ -n "$APP_PATH" ]; then
    open "$APP_PATH"
    echo "✓ App abierta"
else
    echo "✗ No se encontró Tasks.app"
    exit 1
fi
