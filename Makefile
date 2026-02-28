.PHONY: build run run-attached clean

build:
	xcodebuild -scheme Tasks -configuration Debug build

run: build
	@osascript -e 'tell application "Tasks" to quit' 2>/dev/null || true; \
	sleep 1; \
	APP=$$(find ~/Library/Developer/Xcode/DerivedData -name "Tasks.app" -path "*/Build/Products/Debug/*" ! -path "*Index.noindex*" 2>/dev/null | head -1); \
	if [ -n "$$APP" ]; then open "$$APP"; echo "✓ App abierta"; else echo "✗ No se encontró Tasks.app"; exit 1; fi

# Ejecuta la app en la terminal (stdout/stderr visibles, como en Xcode)
run-attached: build
	@osascript -e 'tell application "Tasks" to quit' 2>/dev/null || true; \
	sleep 1; \
	APP=$$(find ~/Library/Developer/Xcode/DerivedData -name "Tasks.app" -path "*/Build/Products/Debug/*" ! -path "*Index.noindex*" 2>/dev/null | head -1); \
	if [ -n "$$APP" ]; then \
		echo "✓ Ejecutando Tasks (Ctrl+C para salir, logs visibles)"; \
		exec "$$APP/Contents/MacOS/Tasks"; \
	else echo "✗ No se encontró Tasks.app"; exit 1; fi

clean:
	xcodebuild -scheme Tasks clean
