#!/usr/bin/env bash
# Simula o POST que a rotina load_api_requests_to_cloudzero envia para a CloudZero.
# Substitua YOUR_CLOUDZERO_TOKEN pelo token (o mesmo do secret CLOUDZERO_API_TOKEN, chave "token").
#
# Uso:
#   export CLOUDZERO_TOKEN="seu-token-aqui"
#   ./cloudzero_api_requests_curl_example.sh
# ou:
#   CLOUDZERO_TOKEN="seu-token" ./cloudzero_api_requests_curl_example.sh

TOKEN="${CLOUDZERO_TOKEN:-YOUR_CLOUDZERO_TOKEN}"
URL="https://api.cloudzero.com/unit-cost/v1/telemetry/metric/quintoandar_api_requests_count/replace"

# Payload idêntico ao gerado pela rotina: records com granularity DAILY, timestamp, value, associated_cost (custom:API)
curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X POST "$URL" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
  "records": [
    {
      "granularity": "DAILY",
      "timestamp": "2025-01-15",
      "value": 125000,
      "associated_cost": { "custom:API": "listing-service" }
    },
    {
      "granularity": "DAILY",
      "timestamp": "2025-01-15",
      "value": 98000,
      "associated_cost": { "custom:API": "search-api" }
    },
    {
      "granularity": "DAILY",
      "timestamp": "2025-01-15",
      "value": 45000,
      "associated_cost": { "custom:API": "auth-service" }
    },
    {
      "granularity": "DAILY",
      "timestamp": "2025-01-15",
      "value": 32000,
      "associated_cost": { "custom:API": "payment-gateway" }
    },
    {
      "granularity": "DAILY",
      "timestamp": "2025-01-15",
      "value": 18000,
      "associated_cost": { "custom:API": "notification-service" }
    }
  ]
}'
