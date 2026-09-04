# ETL Gantt

Local Streamlit app to inspect the latest successful run and median
time-of-day for an Airflow task (or table) and its upstream Airflow jobs,
using Astro `task_instance` (success only).

## Prerequisites

- Python 3.10+
- [uv](https://docs.astral.sh/uv/)
- VPN / network access to Trino
- Browser for SSO on first load

## Usage

```bash
cd local/etl_gantt
chmod +x run.sh
./run.sh
```

`chmod +x` is required on first run if the script is not already executable.

Open the URL Streamlit prints (`http://127.0.0.1:8501`). The server binds loopback only — do not pass `--server.address 0.0.0.0` or otherwise expose the port. The process keeps a live Trino session after SSO, so anyone who can reach the UI can run queries as you.

The first page load opens Trino SSO in the browser. That handshake connects as `_oauth_bootstrap` and is expected to fail with an impersonation denial *after* the token is issued; Trino audit will show that denial on every fresh connect. Later runs reuse the token in the OS keyring. No `TRINO_USER` export is required.

Optional: `TRINO_HOST` (default `trino.apps.data-prd.habitat.zone`). Only `*.habitat.zone` hostnames are accepted. Queries set `source=etl_gantt` and `query_max_run_time=5m`.

Choose **Table name (FQN)** (`schema.table`) or **Task id**, set the date window (default last 30 days, **maximum 30 days inclusive**), optionally cap hop depth (`1` = direct upstreams; hop 0 is always the target), then **Run query**. By default the result is hop 0 plus upstreams whose latest run ended on D0 (the target run's calendar day). **Show dependencies before D0** restores earlier/stale bars (hop 0 is always kept); toggling it requires **Run query**. The default result view is a Plotly Gantt (one bar per table); turn on **Show table** for the tabular rows. A successful run overwrites `output.csv` next to the app. The sidebar **Color by** control defaults to DAG owner and can switch to hop level or DAG id without re-running the query. **Exclude raw layer** / **Exclude clean layer** hide upstream bars whose DAG declaration `workflow.layer` is `raw` or `clean` (hop 0 is always kept) without re-running the query.

Runtime uses successful `datalake_astro_clean.task_instance` rows only.

The cutoff is **per UTC calendar day of `ts_started`, not the Astro dump partition**. `task_instance.year/month/day` are the export snapshot date (incremental dumps overlap d-1 plus today), so they are only used to prune partitions (with a one-day pad). For every UTC day on which the hop-0 producer succeeded, that day’s latest successful `ts_started` is the seed instant, and each upstream task keeps the latest successful run whose `ts_ended` is at or before it — the run that actually fed that day’s seed. The bar is the pick for the most recent seed day; the median is the time-of-day median over every pick. Both therefore describe the same selection rule.

A single global cutoff made those two disagree on multi-slot DAGs. `ebdb_partner` runs `10 21,8,12 * * *`: older days could always pick its late slot, while the seed day could only pick a slot that had already finished, so the bar landed hours away from the median. For `datalake_chatbot.sessions` the hop-3 `partner_agent` median moved from 15:24 to 00:25 against a 00:23 bar once the cutoff went per day — same 31 daily picks, no data dropped.

A producer reached through a `:first-run-of-day` edge in `dependencies.yaml` only emits its dataset once a day, so its later runs never unblock the consumer and are dropped before the cutoff applies (the earliest successful run whose `ts_started` falls on that UTC calendar day; a 21:10 BRT slot is the *first* run of the following UTC day). `inner_dependencies` waits are on the DAG run’s own task instance, so they keep every run; a task reached both ways keeps every run. Hover shows which rule produced each bar.

Bars carry **real UTC timestamps**, not a time of day, so a chain that crosses midnight still reads top-to-bottom in the order it ran. Collapsing every bar onto one dummy date used to invert that: for `datalake_chatbot.sessions` at 05:33, the `copilot_service` run that fed it at 23:56 the evening before was drawn to its right and sorted above it, because `23:56 > 05:33` as a clock reading.

Each row is labelled with its day offset from the target run’s day — `D0` for the target’s day, `D-1` for the day before — and a dashed line marks every midnight in range with the day it opens. Median markers are a time of day with no date of their own, so each one is projected onto the calendar day that puts it next to its own bar, and its hover reports the offset it landed on (`23:50 (D-1)`). Hourly gridlines are dropped once the plotted span passes two days, and midnight lines past a week, so one stale upstream cannot flood the axis.

A **yellow band** shades every span in which none of the plotted tasks was running — the dead time a chain spends waiting rather than working. Coverage is the running union of the bars, so a short run nested inside a longer one does not open a phantom gap, and medians never count as activity because they are a projected time of day, not a run. Each band is labelled with its duration, and the sidebar's **Idle gap threshold (minutes)** (default 15) hides seams shorter than that; `0` shades every gap.

Run selection compares timestamps, never `id_run`. Airflow prefixes the run id with the trigger type (`scheduled__`, `dataset_triggered__`, `manual__`), so string comparison sorts by trigger type before date — a dataset-triggered seed would silently discard every `scheduled__` upstream, and a cron seed would admit dataset-triggered runs newer than itself.

## Job dependencies

Upstream hops are Airflow job edges, not SQL/metadata table lineage:

- `inner_dependencies` (and `raw_inner_dependencies` / `clean_inner_dependencies`) in `dags/**/*_declaration.yml` — tables that must finish first in the same DAG.
- `dags/dependencies.yaml` — cross-DAG `dag_id:task_id` producers, but only for DAGs actually triggered by those datasets.

Only waits Airflow enforces become hops. A DAG that declares `dag.schedule_interval` is skipped when expanding `dependencies.yaml`, because `BaseWorkflow` resolves its schedule as `dag_args.get("schedule_interval", dataset_dependencies)`: the compiler still emits the datasets into the generated stub, but cron wins and the DAG starts on the clock regardless of whether those producers succeeded. Traversal therefore stops at the first cron DAG in the chain. `inner_dependencies` still apply inside a cron DAG, since intra-DAG task order holds however the run was triggered.

Keep in mind that `dependencies.yaml` is DAG-grained: a producer is attributed to every task of the consumer DAG, not only to the tables that read it.

Producer resolution (table to `id_dag` / `id_task`) uses `datalake_dag_inventory_clean.table`.

## Tests

```bash
uv run --directory local/etl_gantt pytest
```
