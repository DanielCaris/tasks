#!/bin/bash
# Crea un sprint cerrado en Jira para probar que no aparezca como seleccionado.
# Uso: JIRA_EMAIL=... JIRA_API_TOKEN=... ./create-closed-sprint.sh [BOARD_ID|PROJECT_KEY]
#
# Si pasas PROJECT_KEY (ej: ST), obtiene el primer board del proyecto.
# Si pasas un número, lo usa como BOARD_ID directamente.
#
# Ejemplo:
#   JIRA_EMAIL=tu@email.com JIRA_API_TOKEN=xxx ./create-closed-sprint.sh ST
#   JIRA_EMAIL=tu@email.com JIRA_API_TOKEN=xxx ./create-closed-sprint.sh 5

set -e
BASE="${JIRA_BASE_URL:-https://dcaris.atlassian.net}"
AUTH="$JIRA_EMAIL:$JIRA_API_TOKEN"

if [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ]; then
  echo "Uso: JIRA_EMAIL=tu@email.com JIRA_API_TOKEN=xxx $0 [BOARD_ID|PROJECT_KEY]"
  echo ""
  echo "Ejemplo con project key (obtiene el primer board):"
  echo "  JIRA_EMAIL=user@mail.com JIRA_API_TOKEN=xxx $0 ST"
  echo ""
  echo "Ejemplo con board ID directo:"
  echo "  JIRA_EMAIL=user@mail.com JIRA_API_TOKEN=xxx $0 5"
  exit 1
fi

INPUT="${1:-}"
if [ -z "$INPUT" ]; then
  echo "Indica BOARD_ID (número) o PROJECT_KEY (ej: ST)"
  exit 1
fi

# Resolver BOARD_ID
if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  BOARD_ID="$INPUT"
  echo "Usando board ID: $BOARD_ID"
else
  PROJECT_KEY="$INPUT"
  echo "Obteniendo board para proyecto $PROJECT_KEY..."
  BOARDS=$(curl -s -u "$AUTH" -H "Accept: application/json" \
    "$BASE/rest/agile/1.0/board?projectKeyOrId=$PROJECT_KEY&maxResults=1")
  BOARD_ID=$(echo "$BOARDS" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
  if [ -z "$BOARD_ID" ]; then
    echo "No se encontró board para proyecto $PROJECT_KEY"
    echo "Respuesta: $BOARDS"
    exit 1
  fi
  echo "Board ID: $BOARD_ID"
fi

# Fechas en el pasado (hace 3 semanas)
START_DATE=$(date -u -v-21d +"%Y-%m-%dT12:00:00.000Z" 2>/dev/null || date -u -d "21 days ago" +"%Y-%m-%dT12:00:00.000Z" 2>/dev/null || date -u +"%Y-%m-%dT12:00:00.000Z")
END_DATE=$(date -u -v-7d +"%Y-%m-%dT12:00:00.000Z" 2>/dev/null || date -u -d "7 days ago" +"%Y-%m-%dT12:00:00.000Z" 2>/dev/null || date -u +"%Y-%m-%dT12:00:00.000Z")
SPRINT_NAME="Cerrado test $(date +%m-%d)"

echo ""
echo "1. Creando sprint '$SPRINT_NAME'..."
CREATE_RESP=$(curl -s -w "\n%{http_code}" -X POST \
  -u "$AUTH" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"name\":\"$SPRINT_NAME\",\"originBoardId\":$BOARD_ID,\"startDate\":\"$START_DATE\",\"endDate\":\"$END_DATE\",\"goal\":\"Sprint de prueba para verificar que no aparece como seleccionado\"}" \
  "$BASE/rest/agile/1.0/sprint")

HTTP_CODE=$(echo "$CREATE_RESP" | tail -1)
HTTP_BODY=$(echo "$CREATE_RESP" | sed '$d')

if [ "$HTTP_CODE" != "201" ]; then
  echo "Error creando sprint (HTTP $HTTP_CODE): $HTTP_BODY"
  exit 1
fi

SPRINT_ID=$(echo "$HTTP_BODY" | grep -o '"id":[0-9]*' | cut -d: -f2)
echo "   Sprint creado con ID: $SPRINT_ID"

echo ""
echo "2. Iniciando sprint (future → active)..."
START_RESP=$(curl -s -w "\n%{http_code}" -X PUT \
  -u "$AUTH" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"name\":\"$SPRINT_NAME\",\"originBoardId\":$BOARD_ID,\"startDate\":\"$START_DATE\",\"endDate\":\"$END_DATE\",\"state\":\"active\"}" \
  "$BASE/rest/agile/1.0/sprint/$SPRINT_ID")

START_CODE=$(echo "$START_RESP" | tail -1)
if [ "$START_CODE" != "200" ]; then
  echo "   Error iniciando sprint (HTTP $START_CODE). Intentando cerrar directamente..."
fi

echo ""
echo "3. Cerrando sprint (active → closed)..."
CLOSE_RESP=$(curl -s -w "\n%{http_code}" -X PUT \
  -u "$AUTH" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"name\":\"$SPRINT_NAME\",\"originBoardId\":$BOARD_ID,\"startDate\":\"$START_DATE\",\"endDate\":\"$END_DATE\",\"state\":\"closed\"}" \
  "$BASE/rest/agile/1.0/sprint/$SPRINT_ID")

CLOSE_CODE=$(echo "$CLOSE_RESP" | tail -1)
if [ "$CLOSE_CODE" != "200" ]; then
  echo "   Error cerrando sprint (HTTP $CLOSE_CODE)"
  echo "   Respuesta: $(echo "$CLOSE_RESP" | sed '$d')"
  exit 1
fi

echo ""
echo "✓ Sprint cerrado creado correctamente."
echo "  ID: $SPRINT_ID"
echo "  Nombre: $SPRINT_NAME"
echo ""
echo "Para probar: asigna una tarea a este sprint en Jira, sincroniza en Tasks"
echo "y verifica que NO aparezca como sprint seleccionado (debe mostrar 'Agregar sprint')."
