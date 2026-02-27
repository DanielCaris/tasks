# Configuración del MCP de Jira

El MCP de Jira ya está instalado en Cursor. Solo necesitas configurar tus credenciales.

## 1. Obtener el API Token de Jira

1. Ve a [Atlassian Account Settings - API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Haz clic en **"Create API token"**
3. Ponle un nombre (ej: "Cursor MCP") y crea el token
4. **Copia el token** (solo se muestra una vez)

## 2. Identificar tu Site (JIRA_BASE_URL)

Tu URL de Jira tiene este formato:
```
https://<tu-organizacion>.atlassian.net
```

Ejemplos:
- `https://miempresa.atlassian.net`
- `https://acme.atlassian.net`

## 3. Editar la configuración

Abre `~/.cursor/mcp.json` y reemplaza los valores en la sección `jira`:

```json
"jira": {
  "command": "npx",
  "args": ["-y", "@answerai/jira-mcp"],
  "env": {
    "JIRA_API_TOKEN": "tu_token_generado",
    "JIRA_BASE_URL": "https://tu-organizacion.atlassian.net",
    "JIRA_USER_EMAIL": "tu-email@empresa.com"
  }
}
```

## 4. Reiniciar Cursor

Reinicia Cursor (o recarga la ventana) para que cargue el MCP de Jira.

---

**Herramientas disponibles con el MCP de Jira:**
- `search_issues` - Buscar issues con JQL
- `get_issue` - Obtener detalles de un issue
- `get_epic_children` - Obtener hijos de un epic
- `create_issue` - Crear issues
- `update_issue` - Actualizar issues
- `add_comment` - Añadir comentarios
- `add_attachment` - Adjuntar archivos
