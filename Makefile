.PHONY: build run clean

build:
	xcodebuild -scheme Tasks -configuration Debug build

run: build
	@APP=$$(find ~/Library/Developer/Xcode/DerivedData -name "Tasks.app" -path "*/Build/Products/Debug/*" 2>/dev/null | head -1); \
	if [ -n "$$APP" ]; then open "$$APP"; echo "✓ App abierta"; else echo "✗ No se encontró Tasks.app"; exit 1; fi

clean:
	xcodebuild -scheme Tasks clean
