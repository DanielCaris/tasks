# Agent Guide

## Build commands

| Command | Description |
|---------|-------------|
| `make build` | Compiles the project (Debug configuration) |
| `make run` | Builds and launches the Tasks app |
| `make run-attached` | Builds and runs the app in the terminal (logs visibles, como en Xcode) |
| `make clean` | Cleans the build artifacts |

## Running the app after changes

After modifying Swift code or project resources, automatically run:

```bash
make run
```

This command builds the project and launches the Tasks app to verify that changes work correctly. Use `make build` alone if you only need to compile without launching.
