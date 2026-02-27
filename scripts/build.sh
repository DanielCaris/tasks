#!/bin/bash
# Compila la app Tasks para macOS
set -e
cd "$(dirname "$0")/.."
xcodebuild -scheme Tasks -configuration Debug build
echo ""
echo "✓ Build exitoso"
