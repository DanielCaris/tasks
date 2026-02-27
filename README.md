# Tasks

App nativa macOS para listar tareas desde Jira, priorizarlas por urgencia/impacto/esfuerzo y mantener una mini-vista flotante siempre visible.

## Requisitos

- macOS 15+
- Xcode 15+
- Cuenta Jira Cloud con API token

## Desarrollo

```bash
# Compilar
./scripts/build.sh
# o: make build

# Compilar y ejecutar
./scripts/run.sh
# o: make run
```

O abre el proyecto en Xcode: `open Tasks.xcodeproj` y usa ⌘R.

## Configuración

1. Compila y ejecuta la app
3. En la app, ve a **Ajustes** (icono engranaje)
4. Configura:
   - **URL base**: `https://tu-empresa.atlassian.net`
   - **Email**: tu email de Atlassian
   - **API Token**: genera uno en [Atlassian Account Security](https://id.atlassian.com/manage-profile/security/api-tokens)
5. Guarda y haz clic en **Actualizar** para sincronizar tareas

## Uso

- **Lista principal**: Muestra tareas asignadas a ti (JQL por defecto: `assignee = currentUser() AND status != Done`)
- **Priorización**: Selecciona una tarea y ajusta Urgencia (1-5), Impacto (1-5) y Esfuerzo (1-5). El score se calcula como `(U × I) / E`
- **Mini vista**: Botón en la barra de herramientas para mostrar/ocultar una ventana flotante con las 5 tareas más prioritarias

## Estructura

```
Tasks/
├── Models/         # TaskItem (SwiftData), IssueDTO
├── Providers/      # IssueProviderProtocol, JiraProvider
├── Stores/         # TaskStore, KeychainHelper
└── Views/          # MainView, TaskRowView, TaskDetailView, MiniView, SettingsView
```

La arquitectura permite añadir otros proveedores (ej. Linear) implementando `IssueProviderProtocol`.
