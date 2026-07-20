# dag_runtime_monitoring

Every 30 minutes this DAG inspects every currently-running DAG and flags any whose
elapsed time is anomalous **relative to that same DAG's own recent successful runs**
(P`percentile` of successful-run durations over the last `lookback_days` × `factor` — no hardcoded per-DAG
thresholds) **and** only once the run has been executing for at least
`min_alert_duration_minutes` (absolute floor, so quick DAGs never alert).

**Every anomaly goes to Google Chat** and is tracked to closure (ledger Variable
`DAG_RUNTIME_MONITORING_ALERTED_RUNS`: initial alert, 30-min updates, ✅/❌ close).

When `critical_dags` is non-empty, findings that are **in the list** or that
**transitively block** one (via `dependencies.yaml`) **also** page JiraOps once.

- **Empty `critical_dags`** (prod soft-launch): Chat only; nothing pages Jira.
- **Critical / blocking critical** → Chat **+** JiraOps.
- **Neither** → Chat only.

**Elapsed clock:** when a run has an `execute-job-cluster` / `execute-job-cluster-N`
task, both live elapsed and the historical baseline start from that task’s earliest
`start_date` (sensor / pre-cluster wait is excluded). Runs still waiting for that task
to start are not evaluated. DAGs without that task keep full `dag_run` wall time.
Metadata lookups join `task_instance` only for the filtered candidate `dag_run` rows
(never a full-table aggregate of every `execute-job-cluster*` TI).

Real alerts are only delivered when `environment == prod`. Config lives in
`prod_conf.yml` / `forno_conf.yml` (`lookback_days`, `min_history_runs`, `percentile`,
`factor`, `min_alert_duration_minutes`, `critical_dags`).

## Downstream DW impact

Each cycle the monitor loads the **deployed** `dags/dependencies.yaml` (same file Airflow
ships with the `dags/` package) via `BietlejuiceDependencyHelper`, builds a reverse
dependency index once, and for every flagged DAG attaches the **transitive** list of
downstream IDs matching `bietlejuice.dw_*`.

- **Initial** Google Chat / JiraOps messages include the full list (truncated after 25
  names with `… and K more`).
- **Follow-up** Chat updates recompute the count from the live YAML so a mid-incident
  deploy that changes the graph is reflected (`Still blocking N dw_* DAG(s)`).
  If the YAML cannot be loaded on a later cycle, the update keeps the ledger's
  snapshot count from the initial alert instead of dropping the blocking line.
- If the YAML cannot be read **or** inverted (invalid upstream shapes) on the
  **initial** alert, messages still send with `• Impacted DW: none` — the
  monitor cycle never fails on a dependency-parse error.

Alert text is multiline (🐌 + owner from Airflow `dag.owners` with fallback to
serialized DAG `default_args.owner`, elapsed/baseline, run id, DW impact). Payloads
are hard-capped before send: Google Chat `text` ≤ 4096 chars; JiraOps/Opsgenie
`message` ≤ 130 and `description` ≤ 15000.

Freshness tracks DAG deploys: after `make dependencies-file` is committed and the
`dags/` package is uploaded to Airflow, the next `*/30` run sees the new graph. No
static list in `prod_conf.yml` is required for impact text.

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
| `critical_dags` | Replace YAML `critical_dags` for this run only (string or list). | YAML value |

**Safety rule:** when `force_send` is set, a *critical* finding is only **paged in
JiraOps** if a `test_responder_team_id` is provided; otherwise Jira is skipped but
**Chat still delivers**. A test trigger can never reach the real Data Engineering
on-call.

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
