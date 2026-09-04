---
name: suggest-lineage-improvements-based-on-etl-gantt
description: >-
  Suggests (does not implement) lineage changes that could pull hop-0 table
  delivery earlier by reading more-upstream sources: passthrough columns,
  simple remaps, inner_dependency serialization, and DAG-grained false waits.
  Classifies Gantt idle gaps as cron schedule_interval (clock wait) vs a
  still-running producer DAG whose SQL deps already finished (split-DAG idea).
  Uses local/etl_gantt/output.csv (or an attached materialization-times CSV)
  plus DAG SQL and declarations. Default focus is hops 1–3; the user may
  name a different hop, hop range, or a clock/time window on the Gantt bars.
  Use when the user asks to improve final-table delivery time from the ETL
  Gantt CSV, look at hops, idle time / idle gaps, find passthrough columns,
  consume further upstream, split a DAG, or shorten Airflow waits without
  changing grain or business logic.
---

# Suggest lineage improvements (read-only)

Advise only. **Do not edit, create, delete, or regenerate any file** (SQL, YAML, `_dag.py`, `dependencies.yaml`, CSV, docs). Do not run `make create-dag-files` or open a PR. End by asking whether the user wants to implement a subset later.

CSV default: `local/etl_gantt/output.csv`. If the user attached another CSV, use that.

Calibration examples: [examples.md](examples.md).

## Scope (hops and time)

Hop 0 is always the target. **Default in-scope hops: 1–3.**

If the user names a hop, hop list, or range, that replaces the default for this turn (examples: “only hop 1”, “hops 2–5”, “hop 4 and below”, “all hops”). Do not also analyze the default 1–3 unless they still overlap the request.

If the user names a **time range**, keep those hops but keep only rows whose seed-day bar overlaps the window (`latest_ts_started` / `latest_ts_ended`). Interpret clock-only times (e.g. 08:00–11:00) on the **seed day’s UTC calendar date** unless the user specifies a timezone (BRT = UTC−3) or asks to filter `median_*_tod` instead. Inclusive bounds. “Last N hours before hop 0” means `[hop0.latest_ts_started − N, hop0.latest_ts_started]`. Hop 0 stays in the intro even if it falls outside the window.

State the applied hop set and time window at the top of the report, plus idle investigation (gaps found or “none ≥ 15 min”). If the filter leaves no SQL sources, say so and stop.

## CSV columns

`level`, `table_name`, `id_dag`, `id_task`, `first_run_of_day`, `latest_ts_started`, `latest_ts_ended`, `median_start_tod`, `median_end_tod`.

Hops are **Airflow job edges**, not SQL lineage. See `local/etl_gantt/README.md` if hop semantics are unclear.

- `inner_dependencies` in `*_declaration.yml` serialize tasks in the same DAG.
- `dags/dependencies.yaml` is **DAG-grained**: a producer is attributed to every task of the consumer DAG, not only tables that read it.
- Cron `schedule_interval` wins over dataset deps; traversal stops at the first cron DAG. Those SQL sources may be missing from the CSV.

`latest_*` is the pick for the most recent seed day; `median_*` is time-of-day over every daily pick. Quote both when they disagree.

## Workflow

### 1. Identify hop 0 and the critical path

Hop 0 = `level == 0` (one row). If missing, ask which FQN was queried.

List **in-scope** hops (default 1–3). Sort the latest in-scope hop level by `latest_ts_ended` descending. The hop-0 `latest_ts_started` is the wait horizon: producers that ended just before it are the bottleneck. Tables that finished hours earlier than hop 0 are out of the delivery-time problem unless the user included them via hop or time scope.

### 2. Separate SQL sources from Airflow-only hops

Read hop 0 `queries/**/*.sql` and `*_declaration.yml` (`inner_dependencies`).

Classify every in-scope table:

| Class | Meaning |
|---|---|
| **SQL source** | Named in hop-0 FROM/JOIN (or only via an inner-dep table that hop 0 reads). |
| **Inner-dep serializer** | Same DAG; hop 0 waits even if SQL could inline the logic. |
| **DAG-grain false wait** | In the CSV, not in hop-0 SQL; likely `dependencies.yaml` DAG grain or a sibling task’s producer. |

Do not propose “consume table X further upstream” for false waits. Flag them as **orchestration**, not lineage.

### 3. Investigate idle gaps (clock vs split upstream)

Idle = the waiting task has not started even though the work it actually needs is already done (same idea as the Gantt yellow bands). Hop 0 first, then other **in-scope** hops with a gap ≥ **15 minutes** (Gantt default; skip shorter gaps as cluster spin-up).

- Waiting start = that row’s `latest_ts_started`.
- Last actual dependency end = max `latest_ts_ended` of **SQL sources** and same-DAG `inner_dependencies` the waiter truly waits on — not DAG-grain false hops.
- Idle window = `[last actual dep end, waiting start]`.

**(a) Waiting DAG is cron-scheduled.** For the waiter’s `id_dag` (`bietlejuice.{dag_name}`), read `dags/**/{dag_name}/*_declaration.yml` `dag.schedule_interval`. A non-empty cron string is **clock-triggered**. Missing / YAML `null` / `None` is dataset-triggered (not this class). Builder cron is **`America/Sao_Paulo`**, not UTC — convert seed-day UTC timestamps when comparing to the next tick. Approximate DAG start as `min(latest_ts_started)` among CSV rows with that `id_dag`. If last actual deps ended **before** the next cron tick and the DAG’s earliest start sits on/after that tick (allow ~15–30 min for cluster), the gap is a **clock wait**: consuming further upstream will not start the DAG earlier. When useful, split a two-part wait: clock until the cron DAG starts, then `inner_dependencies` until hop 0. Traversal still stops at the first cron DAG, so dataset producers of a cron hop 0 may be absent from the CSV — still read the declaration so (a) is not missed.

**(b) Producer DAG still running; real deps already finished.** Split-the-upstream-DAG idea (orchestration, not SQL). For a dataset-triggered waiter (no cron, or after ruling out (a)):

1. Producer `id_dag`s of the **SQL-needed** tasks.
2. Every other CSV row with that `id_dag` (any hop) = sibling tasks in the same producer run.
3. If SQL-needed tasks ended before the idle gap, but a sibling’s bar overlaps the gap or ends later, the waiter is blocked by **other tasks in that DAG**, not by the tables hop 0 reads.
4. Confirm in `dags/dependencies.yaml`: extra `bietlejuice.{producer}:{task}` edges on the **consumer** DAG from the same producer (Airflow `schedule` is the AND of those datasets). If those extras are the late siblings, splitting the producer (needed tables vs the long-running rest) would let the needed datasets fire without waiting for the rest of the run.
5. Producer tables in the declaration that are **not** in the CSV: if they appear on the consumer’s `dependencies.yaml` list, they are split candidates; say timestamps are unknown. Do not query Trino unless hop 0 or timestamps are missing.

Do **not** recommend a split when the late sibling **is** a real SQL source, or when the waiter is cron (a) — clock still gates start; mention a still-running producer only as a secondary note.

### 4. Column-level pass on late SQL sources

For each late in-scope **SQL source**, list columns hop 0 actually uses (SELECT, JOIN, WHERE, CASE). Open that producer’s SQL. Prefer the latest in-scope hop that still blocks hop 0; walk further upstream only for those tables.

Classify each used column:

| Kind | Typical pattern | Lineage move |
|---|---|---|
| **Passthrough** | `SELECT a.col FROM earlier` (rename/cast only) | Read `earlier` if it ends sooner. |
| **Simple logic** | Filter, `CASE`/`IF` remap, `DISTINCT`, equality, small window (`ROW_NUMBER` = 1 on a clean key) | Inline into hop 0 **or** read the producer’s source and copy the few lines. |
| **Real transform** | Multi-source join, address parse, SCD, version grain, heavy windows, business attribution | Do **not** recommend skipping unless hop 0 could drop those columns. |

Then check **when the producer’s sources finished** (their rows in the same CSV). A passthrough whose upstream ended hours earlier is a strong suggestion. A passthrough whose upstream ended *later* is not a delivery win.

If the producer’s DAG started long after its own SQL sources finished, say so: sibling `inner_dependencies` or DAG-grain waits on that producer DAG — still a suggestion, still no edits.

### 5. Semantic gate (must pass)

A suggestion is valid only if grain and meaning stay the same:

- Do not swap enrich `ts_first_listing` for clean `ts_first_publication` (or similar) without stating the definition change.
- Do not drop “last CIQ on listing” / SCD filters that the producer applied.
- Do not recommend a lower layer that violates `raw → clean → enrich → dw → metric` for the hop-0 layer.
- Going to a *later* layer is not an upstream shortcut.

### 6. Estimate, do not oversell

Use seed-day bars: new earliest start ≈ max `latest_ts_ended` of remaining waits; add hop-0 runtime (`latest_ts_ended − latest_ts_started`). Compare to current hop-0 end. Label as **seed-day illustration**, not an SLA guarantee. Mention median if it tells a different story.

Inner-dep inlining saves the wrapper’s runtime **plus** any gap between the wrapper’s source finishing and the wrapper finishing.

## Table links (mandatory in the report)

Every time a **table** is named in the chat report (FQN, bare name, or “hop 0”), make it a markdown link to that table’s pipeline SQL so the user can open it in one click.

Format: ``[`schema.table`](dags/{domain}/{dag}/queries/{layer}/{table}.sql)`` — workspace-relative path, no line numbers. Repeat the same link on later mentions; do not switch to a bare backtick name after the first hit.

Resolve the file once per table and reuse:

1. CSV `id_dag` is `bietlejuice.{dag_name}`. Glob `dags/**/{dag_name}/queries/**/{bare_table}.sql` where `bare_table` is the FQN’s last segment (`datalake_ciq.ciq_listing_purchase` → `ciq_listing_purchase.sql`).
2. If that misses, glob `dags/**/queries/**/{bare_table}.sql`.
3. Prefer the path whose folder matches the producer DAG. If several layers exist, prefer the layer in the FQN/schema (`_clean` → `queries/clean/`, enrich schemas → `queries/enrich/`, `dw_` / `core_` → `queries/dw/` or `queries/enrich/` as the DAG uses).

Do **not** link: DAG ids, task ids, column names, `inner_dependencies` keys unless they are the table, or CSV rows with an empty `table_name`. If no `.sql` exists (Sheets `done-*` tasks, inventory-only), keep the name in backticks and add “(no SQL in repo)” on first mention only.

## Output (chat only)

Lead with hop 0 as a SQL link, seed `latest_ts_*`, **scope** (hops + time window or “hops 1–3, no time filter”), **idle** (gaps ≥ 15 min or none), and the current bottleneck (what hop 0 waited on).

Then:

1. **Do this (passthrough / simple logic)** — linked tables, columns, upstream linked FQN, why meaning is unchanged, seed-day minutes.
2. **Orchestration (no SQL change)** — DAG-grain false hops; producer DAG blocked by a sibling’s upstream; inner_dep that only exists to share a table; **clock wait**; **split upstream DAG**. Link every table still.
   - **Clock wait** — waiting DAG `schedule_interval`, timezone, last actual dep end vs next tick vs DAG start, seed-day minutes.
   - **Split upstream DAG** — producer DAG id, finished SQL-needed tasks (linked), still-running siblings (linked if they have SQL), `dependencies.yaml` extra edges, estimated minutes if the consumer started when the last extra sibling ended. Idea only; do not rewrite YAML.
3. **Do not skip** — real transforms, or upstream that is later/slower. Link every table.
4. **Combined stack** — if the user applied (1) in order, what the new critical path would be (linked tables).

Each item in (1): current source → proposed source → columns → semantic caveat or “none” → estimated minutes. Both sources are SQL links.

Stop. Ask which items, if any, to implement in a later turn.

## Out of scope

- Implementing SQL/declaration changes (user must request that after this report).
- Rewriting `dependencies.yaml` or splitting DAGs unless listed under orchestration as an *idea*.
- Cluster rightsizing (`right-size-cluster`).
- Querying Trino/Databricks unless the CSV is missing hop 0 or timestamps.
