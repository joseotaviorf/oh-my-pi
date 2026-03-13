# Reverse Integration CloudZero DAG

This directory contains the DAG that sends metrics to CloudZero: contracts count from Trino and API request counts from Prometheus via Grafana datasource.

## Files

- `reverse_integration_cloudzero_declaration.yml` - DAG configuration
- `reverse_integration_cloudzero.md` - Detailed documentation
- `spark_jobs/load_contracts_to_cloudzero.py` - Spark job: contracts from Trino → CloudZero
- `spark_jobs/load_api_requests_to_cloudzero.py` - Spark job: API requests from Grafana → CloudZero
- `queries/reverse/contracts_count.sql` - SQL for contracts count
- `cloudzero_quintoandar_api_requests_count_sample.csv` - Sample CSV to create the API requests metric in CloudZero (timestamp, value, API).
- `cloudzero_api_requests_stream_delete_and_recreate.sh` - Script para criar o stream com a dimensão custom:API (curls de delete no README, se precisar remover antes)
- `README.md` - This file

### Creating the API requests metric in CloudZero

Before the DAG can send data, the metric stream must exist in CloudZero. **Por padrão a rotina envia `associated_cost: {"custom:API": "<app>"}`. A API de Unit Cost Telemetry desta conta não aceita CZ:K8s:Workload; use sempre custom:API.**

**0. Dimensão no CloudZero**  
Crie a **Custom Dimension "API"** no CloudZero (Settings ou CostFormation). No stream use **Target Dimension "API"**. Sem isso a API retorna `InvalidKeysException` ou `InvalidRecordsException`.

1. In CloudZero go to **Settings > Telemetry Streams** → **Create New Stream** → **New Unit Cost Metric Stream**.
2. Set **Granularity** to **Daily**.
3. Set **Name** to `quintoandar_api_requests_count` (must match the DAG).
4. **Obrigatório:** add **Target Dimension** named **API**. **Não é possível alterar as target dimensions depois de criar o stream** — se o stream foi criado sem dimensão, apague e crie de novo.
5. Upload the sample CSV `cloudzero_quintoandar_api_requests_count_sample.csv`:
   - Map **Unit value** → column `value`
   - Map **Timestamp** → column `timestamp`
   - Map **Dimension Element** → column `API`
6. Save. After the stream is created, the DAG can send data via API (replace/sum).

### Simular envio à API CloudZero (curl)

O script `cloudzero_api_requests_curl_example.sh` faz um POST igual ao da rotina. Para testar com um token:

```bash
export CLOUDZERO_TOKEN="<valor da chave token no secret CLOUDZERO_API_TOKEN>"
./dags/tech_platform/reverse_integration_cloudzero/cloudzero_api_requests_curl_example.sh
```

Ou em uma linha (substitua `SEU_TOKEN`):

```bash
curl -X POST "https://api.cloudzero.com/unit-cost/v1/telemetry/metric/quintoandar_api_requests_count/replace" \
  -H "Authorization: SEU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"records":[{"granularity":"DAILY","timestamp":"2025-01-15","value":125000,"associated_cost":{"custom:API":"listing-service"}},{"granularity":"DAILY","timestamp":"2025-01-15","value":98000,"associated_cost":{"custom:API":"search-api"}}]}'
```

## Troubleshooting

### `InvalidKeysException` (dimension 'custom:API' is not valid)

Se a API retornar:

```json
{"error": {"type": "InvalidKeysException", "message": "Could not resolve target keys to valid dimension.", "details": ["The dimension 'custom:API' is not valid. No suggestions were found."]}}
```

a **Custom Dimension "API"** ainda não existe na conta CloudZero. Crie-a antes de enviar telemetry: no CloudZero, em **Settings** (ou **CostFormation**), crie uma dimensão customizada de nome **API**. Depois disso, payloads com `associated_cost: {"custom:API": "..."}` passam a ser aceitos.

### `InvalidRecordsException` (The CZ:K8s:Workload dimension is not valid)

Se a API retornar algo como:

```json
{"error": {"type": "InvalidRecordsException", "message": "multiple errors", "errors": [{"error_message": "The CZ:K8s:Workload dimension is not valid", ...}]}}
```

a **API de Unit Cost Telemetry desta conta não aceita a dimensão CZ:K8s:Workload**. Use **custom:API**: crie a Custom Dimension "API" no CloudZero, no stream use Target Dimension **API**, e use o script/curls com `associated_cost: {"custom:API": "..."}` (já é o padrão do job e do script).

### `UnregisteredKeySetException` (target keys do not match)

Se a API CloudZero retornar algo como:

```json
{"error": {"type": "UnregisteredKeySetException", "message": "The target keys provided do not match those previously registered for this stream.", "event_details": {"registered_keys": [], "record_key_set": ["costcontext:API"]}, ...}}
```

o stream foi criado **sem** Target Dimension (`registered_keys: []`), mas a DAG envia registros com `associated_cost: {"custom:API": "..."}`. No CloudZero **não dá para alterar as target dimensions depois de criar o stream**. Solução: apagar o stream `quintoandar_api_requests_count` e criar de novo seguindo os passos acima, garantindo o passo 4 (Target Dimension **API**) e o mapeamento da coluna `API` no CSV.

**Comandos curl para remover e recriar a métrica** (substitua `SEU_TOKEN` pelo token do CloudZero):

```bash
# 1. Remover o stream (pode levar alguns minutos para o nome ficar disponível)
curl -X DELETE "https://api.cloudzero.com/unit-cost/v1/telemetry/quintoandar_api_requests_count" \
  -H "Authorization: SEU_TOKEN"

# Se retornar 404, tentar com /metric/ no path:
# curl -X DELETE "https://api.cloudzero.com/unit-cost/v1/telemetry/metric/quintoandar_api_requests_count" -H "Authorization: SEU_TOKEN"

# 2. Aguardar 2–5 minutos, depois recriar enviando o primeiro payload COM associated_cost (custom:API)
#    — o primeiro replace cria o stream e fixa as target dimensions
curl -X POST "https://api.cloudzero.com/unit-cost/v1/telemetry/metric/quintoandar_api_requests_count/replace" \
  -H "Authorization: SEU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"records":[{"granularity":"DAILY","timestamp":"2025-01-15","value":125000,"associated_cost":{"custom:API":"listing-service"}},{"granularity":"DAILY","timestamp":"2025-01-15","value":98000,"associated_cost":{"custom:API":"search-api"}},{"granularity":"DAILY","timestamp":"2025-01-15","value":45000,"associated_cost":{"custom:API":"auth-service"}}]}'
```

Ou use o script que só cria o stream (usa custom:API):

```bash
export CLOUDZERO_TOKEN="SEU_TOKEN"
./dags/tech_platform/reverse_integration_cloudzero/cloudzero_api_requests_stream_delete_and_recreate.sh
```

## Configuration

### 1. Databricks Secrets
- **CLOUDZERO_API_TOKEN**: CloudZero API token (required for both jobs).
- **GRAFANA_URL** (optional): Base URL of Grafana; default is `https://grafana.apps.shared-prd.habitat.zone`.
- **GRAFANA_DATASOURCE_NAME** (optional): Datasource name in Grafana; default is `metrics-prod`. UID is resolved via API when not using UID.
- **GRAFANA_DATASOURCE_UID** (optional): Datasource UID; if set, name lookup is skipped.
- **GRAFANA_API_TOKEN**: **Grafana service account token** (required for auth and for resolving datasource by name).
- **PROMETHEUS_REQUESTS_QUERY** (optional): PromQL override (range query uses auto step).
- **PROMETHEUS_REQUESTS_DIMENSION_LABEL** (optional): Prometheus label for the dimension value (default: `app`).
- **CLOUDZERO_DIMENSION_KEY** (optional): CloudZero key in `associated_cost` (default: `custom:API`). A API de Unit Cost Telemetry desta conta não aceita CZ:K8s:Workload; manter custom:API.

### 2. SQL Query
The contracts Spark job reads from the reverse table built by `queries/reverse/contracts_count.sql`.

## Usage

The DAG runs automatically every day at 6 AM. For manual execution:

1. Access the Airflow UI
2. Navigate to the DAG `tech_platform.reverse_integration_cloudzero`
3. Click "Trigger DAG"

## Monitoring

Check the logs of the `load_contracts_to_cloudzero` and `export_reverse-api_requests_count` tasks to monitor execution.
