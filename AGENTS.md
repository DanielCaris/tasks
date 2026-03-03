# Agent Guide

## Build commands

| Command | Description |
|---------|-------------|
| `make build` | Compiles the project (Debug configuration) |
| `make build-release` | Compiles the project (Release configuration) |
| `make dist` | Build Release y copia Tasks.app + Tasks.zip a `dist/` para compartir |
| `make run` | Builds and launches the Tasks app |
| `make run-attached` | Builds and runs the app in the terminal (logs visibles, como en Xcode) |
| `make clean` | Cleans the build artifacts |

## Running the app after changes

After modifying Swift code or project resources, automatically run:

```bash
make run-attached
```

This command builds the project and launches the Tasks app in the terminal with logs visible (useful for debugging errors). Use `make build` alone if you only need to compile without launching.
