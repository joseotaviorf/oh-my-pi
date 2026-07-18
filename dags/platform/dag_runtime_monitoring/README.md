# dag_runtime_monitoring

Every 5 minutes this DAG inspects every currently-running DAG and flags any whose
elapsed time is anomalous **relative to that same DAG's own recent successful runs**
(P`percentile` of successful-run durations over the last `lookback_days` × `factor` — no hardcoded per-DAG
thresholds) **and** only once the run has been executing for at least
`min_alert_duration_minutes` (absolute floor, so quick DAGs never alert). Findings are
routed by tier:

- **Critical** (DAGs in `critical_dags`, the top 50 by downstream `dw_*` impact) → JiraOps
  on-caller alert, one per DAG.
- **Standard** (every other running DAG over its baseline) → one batched Google Chat
  message.

Real alerts are only delivered when `environment == prod`. Config lives in
`prod_conf.yml` / `forno_conf.yml` (`lookback_days`, `min_history_runs`, `percentile`,
`factor`, `min_alert_duration_minutes`, `critical_dags`).

## How to test it

The monitor supports an on-demand **test mode** via the trigger `conf`, so you can
exercise the full detect → route → deliver path without waiting for a real slow DAG and
**without paging real on-call**. All keys are optional; an empty conf = a normal run.

| conf key | meaning | default |
|---|---|---|
| `simulate` | Skip the DB and fabricate one critical + one standard finding. | `false` |
| `simulate_dags` | Explicit dag_ids to fabricate findings for. | one critical + one standard |
| `dry_run` | Log the routing decision but send nothing. | `true` for a bare `simulate`; `false` once `force_send` is set (explicit value always wins) |
| `force_send` | Override the `environment == prod` gate so delivery happens in Forno/local. | `false` |
| `test_webhook` | Send standard-tier gchat to this throwaway webhook instead of the configured one. | — |
| `test_responder_team_id` | Route critical JiraOps alerts to this **test** team (adds a `test` tag + `[TEST]` prefix). | — |
| `only_dags` | Restrict real (non-simulated) evaluation to these dag_ids. | — |

**Safety rule:** when `force_send` is set, a *critical* finding is only paged if a
`test_responder_team_id` is provided; otherwise it is downgraded to log-only. A test
trigger can never reach the real Data Engineering on-call.

### 1. Run Airflow locally

```bash
make run-local-environment          # first time; ~3–8 min. UI at localhost:8080 (admin:admin)
# DAGs are bind-mounted; the scheduler re-parses in ~15–30s after edits.
curl -s -u admin:admin http://localhost:8080/api/v1/dags/bietlejuice.dag_runtime_monitoring
# → confirm "has_import_errors": false
```

Set the Airflow Variables you need (Admin → Variables, or the REST API):
`environment`, `JIRA_OPS_ONCALL_APIKEY` (JSON `{"username":..,"token":..,"cloud_id":..}`),
and — only if delivering to gchat — a test webhook.

### 2. Safe dry-run (verifies detection + routing; sends nothing, needs no creds)

```bash
curl -s -u admin:admin -X POST \
  http://localhost:8080/api/v1/dags/bietlejuice.dag_runtime_monitoring/dagRuns \
  -H 'Content-Type: application/json' \
  -d '{"conf": {"simulate": true, "dry_run": true}}'
```

Read the task log and confirm the `[critical]` / `[standard]` routing lines:

```bash
curl -s -u admin:admin \
  "http://localhost:8080/api/v1/dags/bietlejuice.dag_runtime_monitoring/dagRuns/<run_id>/taskInstances/monitor_dag_runtimes/logs/1"
```

### 3. Force a real alert in Forno / locally, to test destinations (verifies the wire, never pages on-call)

`force_send` overrides the `environment == prod` gate, so the alert actually delivers in
Forno or locally. Point it at a throwaway Chat space and a test JiraOps team. `dry_run`
defaults to `false` once `force_send` is set, so you don't need to pass it.

```bash
curl -s -u admin:admin -X POST \
  http://localhost:8080/api/v1/dags/bietlejuice.dag_runtime_monitoring/dagRuns \
  -H 'Content-Type: application/json' \
  -d '{"conf": {"simulate": true, "force_send": true,
                "test_webhook": "https://chat.googleapis.com/v1/spaces/…TEST…",
                "test_responder_team_id": "<test-team-id>"}}'
```

Confirm the message lands in the throwaway Chat space and the `[TEST]`-marked alert
appears in the test Jira team. In the **Forno** Airflow deployment, run the same trigger
from the UI (*Trigger DAG w/ config*) with that conf — `JIRA_OPS_ONCALL_APIKEY` is already
set there; you supply the test webhook + test team id. Omitting `test_responder_team_id`
downgrades the critical alert to log-only (the standard/gchat alert still delivers).

### 4. Test against real running DAGs (no simulation)

Trigger with `only_dags` to evaluate specific DAGs currently running, dry-run first:

```bash
-d '{"conf": {"only_dags": ["bietlejuice.ebdb_location"], "dry_run": true}}'
```

A manual Forno run like the above also satisfies the "Forno run before merge" constraint.

## Unit tests

```bash
uv run --directory packages/bietlejuice-airflow \
  pytest test/unit/dags/platform/dag_runtime_monitoring -q
```
