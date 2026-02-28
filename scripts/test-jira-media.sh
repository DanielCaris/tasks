#!/bin/bash
# Prueba el flujo: attachment ID -> 303 redirect -> extraer UUID del Location
# Uso: ./test-jira-media.sh TU_EMAIL TU_API_TOKEN

set -e
BASE="https://dcaris.atlassian.net"
ISSUE="SON-1"

if [ -n "$1" ] && [ -n "$2" ]; then
  EMAIL="$1"
  TOKEN="$2"
else
  echo "Uso: $0 TU_EMAIL TU_API_TOKEN"
  echo ""
  echo "Ejemplo:"
  echo "  $0 tu@email.com tu_api_token_de_atlassian"
  exit 1
fi

echo "=== 1. Obtener attachments de $ISSUE ==="
ATT_JSON=$(curl -s -u "$EMAIL:$TOKEN" "$BASE/rest/api/3/issue/$ISSUE?fields=attachment")
ATT_ID=$(echo "$ATT_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if 'errorMessages' in d:
    print('AUTH_FAIL', file=sys.stderr)
    sys.exit(1)
atts=d.get('fields',{}).get('attachment',[])
if not atts:
    print('NO_ATT', file=sys.stderr)
    sys.exit(1)
for a in atts:
    fn=(a.get('filename') or '').lower()
    if any(fn.endswith(x) for x in ['.png','.jpg','.jpeg','.gif','.webp']):
        print(a['id'])
        break
else:
    print(atts[0]['id'])
" 2>/dev/null)

if [ -z "$ATT_ID" ] || [ "$ATT_ID" = "NO_ATT" ]; then
  echo "No se encontraron attachments."
  exit 1
fi
if [ "$ATT_ID" = "AUTH_FAIL" ]; then
  echo "Error de autenticación. Verifica email y API token."
  exit 1
fi

echo "Attachment ID: $ATT_ID"
echo ""
echo "=== 2. GET attachment/content (curl NO sigue redirects por defecto) ==="
echo "Respuesta esperada: HTTP 303 con Location: https://api.media.atlassian.com/file/{UUID}/binary?token=..."
echo ""
curl -s -D - -o /dev/null -u "$EMAIL:$TOKEN" \
  "$BASE/rest/api/3/attachment/content/$ATT_ID" | head -25

echo ""
echo "=== 3. El UUID está en Location entre /file/ y /binary ==="
