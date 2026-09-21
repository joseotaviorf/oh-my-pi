# dag_runtime_monitoring

Every 30 minutes this DAG:

1. Inspects every currently-running DAG and flags any whose elapsed time is anomalous
   **relative to that same DAG's own recent successful runs** (P`percentile` of
   successful-run durations over the last `lookback_days` × `factor` — no hardcoded
   per-DAG thresholds) **and** only once the run has been executing for at least
   `min_alert_duration_minutes` (absolute floor, so quick DAGs never alert).
2. Flags DAGs that **should have started by now** (SLA start / missing-run guard)
   based on each DAG's own historical first-start offset within the daily cycle
   (anchored at `sla_cycle_anchor_local_time`, default 20:55 America/Sao_Paulo),
   with dependency-based root-cause suppression so one stalled root produces one
   alert instead of hundreds of downstream noise.
3. Flags DAGs that declare `dag.sla_deadline_localtime: "HH:MM"` and have not had a
   successful run in the current cycle by that São Paulo wall-clock time. The clock is
   local for the same reason the cron schedules are: that is how the business states
   the SLA.

**Every anomaly goes to Google Chat** and is tracked to closure (ledger Variable
`DAG_RUNTIME_MONITORING_ALERTED_RUNS`: initial alert, 30-min updates, ✅/❌ close).

The paging set is **declared, not configured**: `dag.criticality` in each
`*_declaration.yml` becomes the Airflow tag `criticality:<Level>`, and every cycle the
monitor reads those tags out of `dag_tag` (`_fetch_declared_criticality`). `Critical`
and `High` page JiraOps (`CriticalityEnum.PAGING`); `Medium` / `Low` / untagged are
Chat-only. A `critical_dags` trigger conf still replaces the derived set for one run.

- **slow**, declaring Critical/High or transitively blocking one → Chat **+** JiraOps
- **missing-run**, declaring Critical/High → Chat **+** JiraOps
- **missing-run**, blocking a paging DAG without declaring one itself → Chat only
  (the transitive upstreams of the paging set include chronically late DAGs —
  `ebdb_house`, `ebdb_listing`, `bob`, `wololo`, … — late 13–15 of 14 days; paging that
  layer would be an alert storm)
- **deadline-miss**, declaring Critical/High → Chat **+** JiraOps (membership only)
- **everything else** → Chat only

OpsGenie priority comes from the same declaration — Critical → P1, High → P2,
Medium → P3, Low → P4 (`CriticalityEnum.to_opsgenie_priority`) — here and in
`JiraOpsCallback` task/DAG failure alerts.

Root suppression is unchanged: a priority DAG that is late because an upstream is
late is not a root, produces no finding, and therefore no page. The upstream's own
Chat alert remains the signal.

JiraOps alerts are closed by on-call in JSM, never by Rubinho (the Chat thread
still posts the ✅ close).

**Elapsed clock (slowness):** when a run has an `execute-job-cluster` / `execute-job-cluster-N`
task, both live elapsed and the historical baseline start from that task’s earliest
`start_date` (sensor / pre-cluster wait is excluded). Runs still waiting for that task
to start are not evaluated. DAGs without that task keep full `dag_run` wall time.
Metadata lookups join `task_instance` only for the filtered candidate `dag_run` rows
(never a full-table aggregate of every `execute-job-cluster*` TI).

**SLA candidates:** active, unpaused DAGs with a real schedule (dataset or cron).
Excluded by default: `migration_*` prefixes, `__validation` suffixes, and this DAG
itself. Manual-only (`schedule_interval` null) DAGs are skipped. MLOps DAGs
(`quintoml.*`, `wonka*`, and the MLOps-owned `bietlejuice.` DAGs `emlio`,
`enrich_emlio`, `batch_inference`, `evidently_ml_monitor`) never alert on either
check — `alert_exclude_dag_prefixes` is applied to slowness, to SLA candidacy,
and to ledger follow-up. Deadline-miss candidates are that same candidate set
intersected with the DAGs carrying an `sla_deadline_localtime:` tag, so a paused
or manual-only DAG never produces a deadline finding.

**Root selection (missing-run).** Of the DAGs past their due time, only the *roots*
are alerted on. A **confirmed** root is **not blocked on a dataset** and has no late
upstream, with every upstream expected to run this cycle already succeeded. Upstreams
outside the candidate set (paused, deactivated, excluded) can never succeed this cycle,
so they do not block — otherwise their dependents would be permanently unalertable.

**The blocked gate.** A producer counts as delivered the moment it emits *any* outlet,
which is what lets a manual recovery run close its own alert. But blocking is per
*dataset*, so a mid-flight upstream would otherwise mark itself delivered, leave the late
set, and promote its entire downstream wavefront into "confirmed" roots that start on
their own minutes later. That is the 2026-07-25 cascade, where `dw_accounts_receivable`
alerted while still short the one dataset its upstream was computing.

The gate therefore asks whether the upstream is *finished with the specific dataset*,
not whether every dataset is satisfied. A missing dataset is **settled** — and its DAG
is reported, not suppressed — when either its own event fired this cycle (Airflow
dropped the update; the queue row will never appear) or its producer completed a
successful run without delivering it. Only a DAG whose every missing dataset is still
being worked on is suppressed.

Gating on plain satisfaction instead is what broke prod on 2026-07-26: a DAG stuck at
13/14 fails that test, so the dropped-event case the guard exists for was silenced and
every tick reported 0 roots while 13 → 38 DAGs sat late. Run completion is read from
real runs only, never from emissions, which is what keeps the 2026-07-25 avalanche
fixed; the URI check covers what run history cannot see, since a recovery run is
excluded from history but does emit real events.

If nothing is confirmed but *unblocked* DAGs are still late — e.g. the true root has too
little history to have a baseline — the monitor falls back to the **tops of the late
subgraph**. Those findings still carry `root_is_fallback` / `late_count` in the
ledger for diagnostics; Chat stays compact and does not surface an Attribution
line. A lower-confidence root beats going silent during a real cascade, which is
the failure mode the 2026-07-14 postmortem describes. The fallback distinguishes
*missing information* from *known blockage*: when the dataset trigger state cannot be
read at all, every late DAG stays eligible and the guard fails open; when it reads
cleanly and says "blocked", that is evidence and the DAG stays silent.

**Required datasets.** `BietlejuiceDatasetService` schedules a DAG as
`any(all(<first-run-of-day>), any(<reprocessing>))`, but `dag_schedule_dataset_reference`
stores a flat dataset list and loses the AND/OR structure. Only the non-reprocessing
branch gates a normal cycle, so the twins are excluded from both the satisfaction
quotient and the blocked gate — counting them made a ready DAG read as
blocked (`dw_accounts_receivable` showed `3/7` while short exactly one real dataset, and
now reads `3/4`). The twin is the dependency string with `:reprocessing` appended, and
the dependency usually already carries its own `:first-run-of-day` variant (4373 of the
4450 declared in `dependencies.yaml`), so a twin is matched on the suffix rather than on
a fixed segment count. A reprocessing-only schedule collapses to no requirement and is
treated like a cron DAG.

**Dependency graph sources.** The upstream/downstream indexes are the **union** of
`dependencies.yaml` and the live dataset-scheduling edges read from the metadata DB
(`dag_schedule_dataset_reference`, joined to `dataset`) — the exact graph
Airflow's own scheduler walks. The YAML is a static approximation that omits whole
namespaces: every `quintoml.*` DAG appears there only as an upstream *value*, never as
a dependent *key*, so without the live edges those DAGs have no upstreams at all and
always alert as their own root. The union also lengthens DW blast radius, because paths
that hop through a missing namespace (`bietlejuice.x → quintoml.y → bietlejuice.dw_z`)
now resolve. Either source may fail on its own; only when **both** are unavailable does
the graph count as missing (fail-closed for detection, ledger snapshot for follow-ups).

**Producer attribution.** An edge needs a producer, and the obvious source —
`task_outlet_dataset_reference` — only holds rows for *statically declared* outlets, so
it is empty for DAGs that publish theirs dynamically. Inner-joining against it was worse
than useless: the live graph came back with no edges at all and silently
stopped suppressing anything, while every missing dataset went unattributed and the
dropped-event verdict could never render. Every dataset URI starts with the producer's
`<dag_id>`, so the producer is recovered from that prefix and unioned with whatever the
reference table does have. Everything after the first separator is treated as opaque,
because the rest varies: `<task_id>`, `<task_id>:first-run-of-day`, or either of those
with `:reprocessing` appended. Both counts are logged every cycle (`🔗 Live dataset graph: N edge(s)…`
and `🔗 Dataset trigger state: … M without a producer`) so an inert graph is visible
directly instead of being inferred from alerts that never name a producer.

**Dataset diagnostics (missing-run).** For each reported root the monitor reads that
DAG's dataset trigger state and adds it to the alert. `dataset_dag_run_queue` rows are
only consumed when a run is actually created, so a DAG that never ran still exposes its
partial queue; the difference against its schedule references names the exact dataset
whose update went missing. Two verdicts:

- **Likely a dropped dataset event** — every condition is queued, or a missing dataset's
  producer already delivered this cycle. This is the postmortem signature: Airflow
  silently drops a dataset update that lands while the target DAG's `SerializedDagModel`
  is stale and never retro-applies it, so the DAG sits at N-1/N forever. The alert names
  the verdict (and cause) in Chat; operators recover with a manual trigger carrying
  `{"run_type": "impact_downstream_dependents"}` — the only form that fans out to
  dependents (a bare manual trigger resolves to `TEST_RUN` and emits nothing).
- **Waiting on `<dag>`** — a producer genuinely has not delivered yet, so the blocking
  upstream is named instead of a dropped-event verdict.

Cron DAGs (no dataset schedule) keep the original message. A failure to read the dataset
tables just drops these bullets; the alert still sends.

**Closing on remediation.** A DAG counts as started this cycle when it has an automatic
run **or** published a dataset event (`dataset_event.source_dag_id`). The manual recovery
run above is invisible to the run-type filter but its emissions prove the chain moved,
so the thread closes with `started at HH:MM` instead of re-firing every 30 minutes until
rollover. Emission likewise counts as "upstream succeeded" for root confirmation. The P90
**baseline** stays automatic-runs-only, so manual reruns never drift the expected offset.

Real alerts are only delivered when `environment == prod`. Config lives in
`prod_conf.yml` / `forno_conf.yml` (`lookback_days`, `min_history_runs`, `percentile`,
`factor`, `min_alert_duration_minutes`). SLA keys
(`sla_enabled`, `sla_lookback_days`, `sla_min_history_cycles`, `sla_percentile`,
`sla_grace_minutes`, `sla_cycle_anchor_local_time`, `sla_exclude_dag_prefixes`,
`sla_exclude_dag_suffixes`, `sla_max_missing_run_alerts`, `alert_exclude_dag_prefixes`)
fall back to module defaults
when omitted.

`sla_max_missing_run_alerts` (default 25) caps how many roots one tick may report,
keeping the latest and adding `Alert cap reached: N more late root(s) not reported` to
the survivors. The blocked gate keeps a recovering cascade quiet on its own, so this
only bites on the one path the gate cannot cover — an unreadable dataset trigger state,
where the fallback deliberately opens up.

## Downstream DW impact

Each cycle the monitor loads the **deployed** `dags/dependencies.yaml` (same file Airflow
ships with the `dags/` package) via `BietlejuiceDependencyHelper`, builds a reverse
dependency index once, and for every flagged DAG attaches the **transitive** list of
downstream IDs matching `bietlejuice.dw_*`.

- **Initial** Google Chat / JiraOps messages include the list with the `bietlejuice.`
  prefix stripped (truncated after 25 names with `… and K more`).
- **Follow-up** Chat updates recompute the count from the live YAML so a mid-incident
  deploy that changes the graph is reflected (`Still blocking N dw_* DAG(s)`).
  If the YAML cannot be loaded on a later cycle, the update keeps the ledger's
  snapshot count from the initial alert instead of dropping the blocking line.
- If the YAML cannot be read **or** inverted (invalid upstream shapes) on the
  **initial** alert, messages still send with `• Impacted DW: none` — the
  monitor cycle never fails on a dependency-parse error.
- For **missing-run detection**, the same load failure is **fail-closed**: no new
  SLA roots are opened that cycle (an empty upstream map would otherwise treat
  every late DAG as a root). Existing SLA ledger entries are still followed up.
- Missing-run **initial** alerts fold due time into `Late by`, keep compact dataset
  diagnostics, list Impacted DW (prefix-stripped) with `· also waiting: N` when
  other late DAGs sit downstream of the root, and omit Trigger / runbook / Attribution
  / tracking-footer noise. **Follow-ups** stay short (`still has not started` + Late by
  + separate `Also waiting downstream` when > 0).
- `sla_enabled: false` stops new missing-run alerts **and** drops any open SLA
  ledger entries without further Chat updates. Paused / inactive / excluded DAGs
  are likewise dropped from the SLA ledger on the next cycle (no more “still
  missing” churn until rollover).
- A bad `sla_cycle_anchor_local_time` falls back to `20:55` so the whole monitor
  (including slowness) keeps running.

Alert text is multiline (🐌/⏰ + owner from Airflow `dag.owners` with fallback to
serialized DAG `default_args.owner`, elapsed/baseline or SLA late-by, run id for
slowness, DW impact).
Payloads are hard-capped before send: Google Chat `text` ≤ 4096 chars; JiraOps/Opsgenie
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
| `simulate` | Skip the DB and fabricate findings. | `false` |
| `simulate_missing_runs` | With `simulate`, fabricate SLA missing-run findings instead of slow ones. | `false` |
| `simulate_dags` | Explicit dag_ids to fabricate findings for. | one critical + one standard (slow); or one missing-run id |
| `simulate_state` | Follow-up phase: `running` / `success` / `failed` (slow) or `running` / `started` (missing-run). | initial |
| `dry_run` | Log the routing decision but send nothing. | `true` for a bare `simulate`; `false` once `force_send` is set (explicit value always wins) |
| `force_send` | Override the `environment == prod` gate so delivery happens in Forno/local. | `false` |
| `test_webhook` | Send gchat to this throwaway webhook instead of the configured one. | — |
| `test_responder_team_id` | Route critical JiraOps alerts to this **test** team (adds a `test` tag + `[TEST]` prefix). | — |
| `only_dags` | Restrict real (non-simulated) evaluation to these dag_ids. | — |
| `critical_dags` | Replace YAML `critical_dags` for this run only (string or list). | derived from criticality: tags |

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

Missing-run path:

```bash
-d '{"conf": {"simulate": true, "simulate_missing_runs": true, "dry_run": true}}'
```

Read the task log and confirm the `[critical]` / `[standard]` / `[missing_run]` routing lines:

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

### 4. Test against real running DAGs / real SLA history (no simulation)

Trigger with `only_dags` to evaluate specific DAGs, dry-run first:

```bash
-d '{"conf": {"only_dags": ["bietlejuice.enrich_region"], "dry_run": true}}'
```

A manual Forno run like the above also satisfies the "Forno run before merge" constraint.
Use it after deploy to sanity-check computed `due_at` values in the task log before
enabling Chat delivery in prod.

## Unit tests

```bash
uv run --python 3.12 --directory packages/bietlejuice-airflow \
  pytest test/unit/dags/platform/dag_runtime_monitoring -q
```