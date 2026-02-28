#!/bin/bash
# Ejecuta la app Tasks como Xcode (Cmd+R): compila y lanza la aplicación
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# DerivedData local al proyecto (evita conflictos con otros proyectos "Tasks")
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/Tasks.app"

echo "🔨 Compilando..."
xcodebuild -scheme Tasks -configuration Debug build \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS' \
  -quiet

if [ -d "$APP_PATH" ]; then
    echo "▶️  Ejecutando Tasks.app"
    open "$APP_PATH"
    echo "✓ App en ejecución"
else
    echo "✗ Error: No se encontró Tasks.app en $APP_PATH"
    exit 1
fi
