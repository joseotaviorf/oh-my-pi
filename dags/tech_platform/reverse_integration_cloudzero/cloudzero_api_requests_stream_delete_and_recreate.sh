#!/usr/bin/env bash
# Cria o stream quintoandar_api_requests_count com a dimensão custom:API (primeiro envio define as target dimensions).
# Pré-requisito: criar no CloudZero a Custom Dimension "API" (Settings/CostFormation) e no stream usar Target Dimension "API".
# A API de Unit Cost Telemetry desta conta não aceita CZ:K8s:Workload; use sempre custom:API.
#
# Pré-requisito: CLOUDZERO_API_TOKEN (chave "token") ou variável CLOUDZERO_TOKEN.
#
# Uso:
#   export CLOUDZERO_TOKEN="seu-token"
#   ./cloudzero_api_requests_stream_delete_and_recreate.sh
#
# Ou com token inline:
#   CLOUDZERO_TOKEN="seu-token" ./cloudzero_api_requests_stream_delete_and_recreate.sh

set -e

TOKEN="${CLOUDZERO_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  echo "Defina CLOUDZERO_TOKEN (ou use o token do secret CLOUDZERO_API_TOKEN)."
  exit 1
fi

STREAM_NAME="quintoandar_api_requests_count"
REPLACE_URL="https://api.cloudzero.com/unit-cost/v1/telemetry/metric/${STREAM_NAME}/replace"

echo "=== Criar stream (POST replace com custom:API define as target dimensions) ==="
curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "$REPLACE_URL" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
  "records": [
    { "granularity": "DAILY", "timestamp": "2025-01-15", "value": 125000, "associated_cost": { "custom:API": "listing-service" } },
    { "granularity": "DAILY", "timestamp": "2025-01-15", "value": 98000,  "associated_cost": { "custom:API": "search-api" } },
    { "granularity": "DAILY", "timestamp": "2025-01-15", "value": 45000,  "associated_cost": { "custom:API": "auth-service" } },
    { "granularity": "DAILY", "timestamp": "2025-01-15", "value": 32000,  "associated_cost": { "custom:API": "payment-gateway" } },
    { "granularity": "DAILY", "timestamp": "2025-01-15", "value": 18000,  "associated_cost": { "custom:API": "notification-service" } }
  ]
}'

echo ""
echo "Se retornar 2xx, o stream foi criado com a dimensão API. A DAG pode enviar dados normalmente."
