#!/bin/bash
# Añade issues a un sprint vía Jira Agile REST API
# Uso: JIRA_EMAIL=tu@email.com JIRA_API_TOKEN=xxx ./add-to-sprint.sh SPRINT_ID ISSUE_KEY1 ISSUE_KEY2 ...
# Ejemplo: JIRA_EMAIL=user@mail.com JIRA_API_TOKEN=xxx ./add-to-sprint.sh 2 ST-1 ST-2 ST-3

set -e
BASE="${JIRA_BASE_URL:-https://dcaris.atlassian.net}"

if [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ]; then
  echo "Uso: JIRA_EMAIL=tu@email.com JIRA_API_TOKEN=xxx $0 SPRINT_ID ISSUE_KEY..."
  echo ""
  echo "Ejemplo:"
  echo "  JIRA_EMAIL=user@mail.com JIRA_API_TOKEN=xxx $0 2 ST-1 ST-2 ST-3"
  exit 1
fi

SPRINT_ID="$1"
shift
if [ -z "$SPRINT_ID" ] || [ $# -eq 0 ]; then
  echo "Debes indicar SPRINT_ID y al menos un ISSUE_KEY"
  exit 1
fi

ISSUES=$(printf '"%s",' "$@" | sed 's/,$//')
BODY="{\"issues\": [$ISSUES]}"

curl -s -X POST \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$BODY" \
  "$BASE/rest/agile/1.0/sprint/$SPRINT_ID/issue"

echo ""
