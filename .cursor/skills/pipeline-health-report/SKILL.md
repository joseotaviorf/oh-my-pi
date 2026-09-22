---
name: pipeline-health-report
description: >-
  Generates a pipeline-health ritual report for one Analytics Engineering team
  over the last 15 days: daily Data SLA, missed-SLA DAGs with root cause
  (including upstream DAGs owned by another team), Google Drive postmortems
  as SLA root-cause evidence, open DEI incident cards (To Do / In Progress),
  Grafana Databricks cluster pressure (spill, swap, memory, CPU), and
  data-quality alerts. The final deliverable is a Cursor canvas (shareable
  team URL via Publish). Use when the user asks for pipeline health, ritual de
  pipeline health, health check de DAGs de um time, relatório de SLA do time,
  causa raiz de SLA, or a weekly/biweekly pipeline health report.
---

# Pipeline Health Report

Read-only operational report. **Do not edit** SQL, YAML, DAGs, or Jira cards.

**É de extrema importância SEMPRE verificar a cadeia de dependências antes de afirmar a causa de um atraso.** Sem `dags/dependencies.yaml` lido para **cada** DAG×dia fora de SLA, e sem o SLA (com timestamp) de **cada** produtor YAML daquele snapshot, **é proibido** escrever cascata interna, cascata externa, “atrasou porque X”, ou duração própria por exclusão. Sem essa verificação a causa é **Indeterminada**. Coincidência no mesmo dia não é cadeia.

Default window: **last 15 calendar days through today** (BRT). Today is a **partial** snapshot (DW/Airflow may still be running). Override only if the user names another window.

Report language: **match the user** (ritual prompts are usually PT-BR).

## When to use

- "ritual de pipeline health", "pipeline health do time X"
- Daily/weekly SLA review for a squad
- "quais DAGs furaram SLA e por quê", incluindo atraso de outro time
- Open DEI incidents + DQ alerts + cluster spill/swap/CPU/memory for a team
- A shareable Cursor canvas of that ritual (not a markdown dump, not a Google Doc)

## Prerequisites

| Need | How |
|------|-----|
| Team name | Ask if missing. Resolve aliases in [aliases.md](aliases.md). |
| Trino | Prefer **Trino MCP** (`mcp_auth` then `execute_query`). Fallback: [`trino` skill](../trino/SKILL.md) `uv run --script …/execute_trino.py --external-auth` with unrestricted permissions (SSO/keyring). Never `@tars`. |
| Jira DEI | **Atlassian MCP** (`plugin-atlassian-atlassian`). Call `mcp_auth` `{}` if `needsAuth`. Then `GetDynamicTools` and use `searchJiraIssuesUsingJql`. |
| Grafana | **Observability MCP** `query_metrics`. Primary dashboard (most DAGs, EMR): [Spark clusters DAGs overview](https://grafana.apps.shared-prd.habitat.zone/d/een6dh4u4aqdcd/spark-clusters-dags-overview?orgId=1&from=now-24h&to=now&timezone=browser&var-env=prod&var-project=bietlejuice&var-dag_name=). Filter `var-dag_name`. Leftover Databricks DAGs: [Databricks clusters comparison](https://grafana.apps.shared-prd.habitat.zone/d/2_zM2pZ4z/databricks-clusters-comparison-between-dags?orgId=1&from=now-24h&to=now&timezone=browser&var-env=prod&var-project=bietlejuice). |
| Postmortems | **Google Drive MCP** (`plugin-google-drive-google-drive`). Folder: [Postmortems](https://drive.google.com/drive/folders/1-Hxx5YPtJmeKhoNe2zW5P9Iohf7Cg_Oi). See [postmortems.md](postmortems.md). |
| Canvas | **Required deliverable.** Read `~/.cursor/skills-cursor/canvas/SKILL.md`, write one `.canvas.tsx`, then tell the user to **Publish** for a shareable team URL. Do not dump tables in chat. |

SQL, PromQL, and JQL live in [queries.md](queries.md). Substitute `<LINE_NAME>`, `<LOOKBACK_DAYS>` (default `15`), and date bounds. Always partition-prune (`year` / `month` / `day`).

## Workflow

Copy and track:

```
Pipeline health:
- [ ] 0. Resolve team + window
- [ ] 1. Daily SLA
- [ ] 2. Missed-SLA DAGs + root cause
- [ ] 2a. YAML chain for every missed DAG×day (mandatory before any cause)
- [ ] 2b. Producer SLA + timestamps for those YAML producers (collapse duplicate rows)
- [ ] 2c. Select worst days (median − 5 pp; 3–6 days; no adjacent glue)
- [ ] 3. Open DEI cards
- [ ] 4. Grafana cluster pressure
- [ ] 5. Data-quality alerts
- [ ] 6. Write Cursor canvas + Publish instructions (shareable link)
```

Run steps **1, 3–5 in parallel** after step 0 (Trino SLA + misses, Trino DQ, Jira, Grafana). Step 2 **blocks** on 2a→2b before any cause sentence: missed-DAG list → **`dags/dependencies.yaml` for every miss** → producer SLA/timestamps → Drive postmortems ([postmortems.md](postmortems.md)). Step 2c runs after the daily SLA series exists. Do not fill the Fora-de-SLA recorte until 2c is done.

### 0. Resolve team and window

If the user did not name a team, **AskQuestion** with the `line_name` values in [aliases.md](aliases.md).

1. Map the user string → canonical **`line_name`** (Airflow owner, e.g. `Data ForRent`) and **Incident Owner** (DEI field, e.g. `Data For Rent`).
2. Confirm in Trino (`queries.md` § line lookup). If zero rows, list distinct `line_name` and ask again.
3. Window: `dt_from = current_date - <LOOKBACK_DAYS>` through `dt_to = current_date` (today inclusive). Label today **parcial**. If DW has no `dt_snapshot` yet, compute from `dag_sla_information` with the eligible-DAG formula. State BRT dates at the top of the report.

Keep the team's `id_dag` list for Grafana/DQ/Jira filtering (`queries.md` § team DAGs).

### 1. Daily SLA

Query `dw_pipeline.fact_pipeline_metrics` ⨝ `dw_pipeline.dim_line` (`queries.md` § daily SLA). **Prefer this number** — do not recompute the ratio in Trino with integer `COUNT` (it truncates to 0).

If a day is missing from DW, compute from `datalake_pipeline.dag_sla_information` using the **same eligible-DAG definition** as `fact_pipeline_metrics.sql` (non-intraday; active+unpaused and not ignored, **or** special-scheduler executed) and cast the ratio as `DOUBLE` before dividing.

For each day record: `dt_snapshot`, `sla` (%), `total_dags_inside_sla`, `total_dags_outside_sla`, eligible denominator.

`total_dags_outside_sla` on the fact counts **all** `is_outside_sla` rows (including ignored). The ritual miss list in step 2 is the **eligible** subset.

### 2. Missed-SLA DAGs and root cause

For every day with `sla < 100` (or eligible misses > 0), list DAGs with `is_outside_sla = TRUE` (`queries.md` § missed DAGs).

Skip intraday / ignoring-list / exclusion-list rows — they are not in the SLA denominator.

**Gate (do not skip):** for every missed DAG×day, **before** picking a bucket:

1. Open the consumer key in `dags/dependencies.yaml`.
2. List producers (substring before the first `:`). Exact name (`ebdb_house_fast_lane` ≠ `ebdb_house`).
3. Query SLA + `ts_first_execution_success_brt` for those producers on the **same** `dt_snapshot` (`queries.md` § upstream — **do not** filter `is_outside_sla`).
4. Classify only after that. No YAML, or no producer timestamp → **Indeterminada**.

**Per DAG × day**, pick a technical bucket first (first match wins; still mention secondary evidence), then overlay Drive postmortems:

| Bucket | When |
|--------|------|
| **Falha própria** | `is_run_failed` or run `state = 'failed'` |
| **Duração própria** | Run succeeded (`is_run_successful`) but `is_outside_sla` — finished after layer SLA (`brt_sla_hour`: 08:00 raw/clean/enrich/dw/metric, 10:00 datamart, 12:00 reverse) |
| **Cascata interna** | ≥1 **YAML** upstream (same `id_line`) that actually missed SLA that snapshot day (after the duplicate-row collapse below) |
| **Cascata externa** | ≥1 **YAML** upstream (**other** `id_line` or `quintoml.*`) that actually missed SLA that day — **this is the question the ritual cares about**. Same-day miss of a DAG that is **not** a producer of this consumer is coincidence, not cascade. |
| **Plataforma** | DEI card that day with category Databricks / Airflow / Hive / Unity Catalog / Mediator |
| **Data quality** | Blocking DQ `table_status = 'error'` on a table of this DAG that day |
| **Indeterminada** | No signal above |

**Postmortem overlay** (after the table): search [the Drive folder](https://drive.google.com/drive/folders/1-Hxx5YPtJmeKhoNe2zW5P9Iohf7Cg_Oi) per [postmortems.md](postmortems.md). A matching PM **upgrades** the primary cause:

- **Postmortem (plataforma)** beats cascata externa / Plataforma when the PM is shared infra (Databricks, Airflow, Glue, Trino, Salesforce, Amplitude, …) on that day.
- **Postmortem (time)** beats falha/duração própria when the PM names this DAG or this team's pipeline.

Always cite the Drive `viewUrl`. Do not copy people names from Owner/Contributors.

**Upstream resolution (obrigatório para qualquer causa de atraso)**

1. In `dags/dependencies.yaml`, key = consumer `id_dag` (`bietlejuice.<dag_name>`). Missing key → no known chain → **Indeterminada**, not cascata.
2. Each value is `bietlejuice.<producer>:<task>…` or `quintoml.…`. Producer `id_dag` = substring before the first `:`. Use the **exact** producer name (`ebdb_house_fast_lane` is not `ebdb_house`).
3. Deduplicate producers. Query their `dag_sla_information` for the **same `dt_snapshot`** — **do not** `AND is_outside_sla = TRUE` (see duplicate-row pitfall).
4. Collapse rows per `id_dag`: if any row has `is_inside_sla = TRUE` and a non-null `ts_first_execution_success_brt` before the consumer's layer SLA, the producer did **not** miss. A sibling row with `is_outside_sla = TRUE` and null timestamp is a ghost.
5. Join producer `id_line` / `line_name`. Cascata externa only with **(YAML edge) AND (collapsed producer missed) AND (`id_line` ≠ team)**. Quote producer `id_dag`, `line_name`, and `ts_ok`. YAML edge + producer inside SLA → **duração própria** (or cascata interna if a same-line YAML producer missed). Same-day miss **without** a YAML edge → not cascade.

If both own duration and an external **YAML** upstream miss exist, set primary = **cascata externa** and note own runtime as secondary — **unless** a platform postmortem covers that day, in which case primary = **Postmortem (plataforma)**.

Do **not** invent a root cause. If Trino/Jira/YAML/Drive disagree, say what is known and label **Indeterminada**. Never put a DAG name in “Causa do dia” as the reason another DAG was late unless that name is a YAML producer of that consumer.

**What goes in the canvas vs what stays in the agent check:** YAML + producer timestamps are mandatory before classifying. The report **names an upstream only when it actually delayed the consumer**. Do not list producers that finished on time (jaiminho, rede_platform, …) to say they were not the cause — that reads as if they were.

### 2c. Which days go in “recorte dos piores dias”

This table is **not** every miss and **not** “today because it is partial”. Compute it from the daily SLA series already in the report (same `fact_pipeline_metrics.sla` numbers).

1. **Baseline** = median of the daily SLA % values in the window (include today if it has a number).
2. **Include** a calendar day iff `sla_day ≤ baseline − 5.0` (five percentage points).
3. If that set has **fewer than 3** days, take the **3 lowest** SLA days instead.
4. If that set has **more than 6** days, keep the **6 lowest**.
5. **One day = one inclusion.** Do not glue D+1 onto D because of residue (12/09 at 98% next to 11/09 is not a worst day).
6. **Today** is included only if it passes (2)–(4). It still belongs in the daily table and the callout.

On each included day, one or more cause-rows are fine. Do not add DAG groups from a day that did not qualify.

Show the median, the cutoff, and which days qualified in the table caption.

### 3. Open DEI incidents

Board: [DEI](https://quintoandar.atlassian.net/jira/software/projects/DEI/boards/437). Project `DEI`. Statuses **To Do** and **In Progress** only (currently open — not a 15-day history).

`cloudId`: `8a4667b7-87a1-4c6c-805c-fc0d6e60a7a0`  
To find the team's cards: match `summary` to a team `id_dag` (and/or DAG Owner). Do **not** put Jira field-debug notes (deprecated Incident Owner, empty custom fields) in the canvas caption.

Always:

1. Try owner JQL (`queries.md` § DEI).
2. Fetch all DEI To Do / In Progress (`maxResults` 100, `view: evidence`) and **keep cards whose `summary` matches a team `id_dag`** (`bietlejuice.<dag_name>` or the bare dag name).

For each card: key, DAG, status, Incident Category, SLA affected, **assignee** (`Não` if null, otherwise displayName). **Do not** include Failed Task on the canvas. URL `https://quintoandar.atlassian.net/browse/<KEY>`.

### 4. Grafana — cluster pressure

Most bietlejuice DAGs run on **EMR**. Some still run on **Databricks**. Prometheus series are the same family (`project="bietlejuice"`); Grafana label is `cluster_name` = **bare DAG name** (`dw_demand`, not `bietlejuice.dw_demand`). The EMR dashboard variable is `dag_name` (maps to that `cluster_name`). Job clusters may still be `{id_dag}_{run_id}` — match either form.

Use Observability MCP `query_metrics` with PromQL from `queries.md` § Grafana. `source=thanos`. Try `cluster=data-prd` first; if zero series, retry `shared-prd`. Range in PromQL: `[15d]` (Thanos may downsample to `1h` — that is fine).

Keep series whose `cluster_name` equals or starts with a team DAG name (strip the `bietlejuice.` prefix from `id_dag`).

Flag (any cluster of a team DAG in the window):

| Signal | Flag when |
|--------|-----------|
| Spill (`diskBytesSpilled`) | `> 0` |
| Swap (`MemorySwap`) | `> 0` |
| Total memory (Used/Total) | `≥ 0.80` high, `≥ 0.90` critical |
| Relative CPU (`1 - IdleCPU`) | `≥ 0.80` high, `≥ 0.90` critical |

Classify each flagged DAG as **EMR** or **Databricks** from the repo (`*_cluster.yml` type `emr_*` vs `databricks_conn_id` / legacy Python Databricks). Render **two tables**. CPU on the canvas: “quanto do tempo o cluster passou trabalhando (não parado)”; flag ≥ 80%. Do not write “1 − ociosa” or “preencha dag_name”.

Dashboard bar gauges are last **24h**; the ritual uses **15d max**. Caption: team DAGs only; 15d max; spill/swap &gt; 0; memory ≥ 80/90%; CPU ≥ 80% working time or none. Link EMR dashboard on the EMR table, Databricks dashboard on the Databricks table. If MCP is down, paste both URLs — do not block the rest of the report.

### 5. Data-quality alerts

First check freshness of **both** `hive.datalake_data_quality.validations` and `hive.datalake_inmetro_clean.data_validations` (`queries.md` § DQ freshness). `enrich_data_quality` only republishes what Inmetro already tested: the enrich SQL filters `MAKE_DATE(year, month, day)` to `{load_start_date}`–`{load_end_date}`. If **neither** table has a partition inside the ritual window, the origin stopped. A later incremental run reads that empty window, writes zero rows, and still succeeds in Airflow. Green Airflow does not fill the hole.

On the canvas, say in plain language: the enrich DAG is running; there is no partition in the window on the Inmetro source or on the enrich table; the last day with a row is DATE; name one incremental execution date in the window that queried an empty window, wrote zero new rows, and finished success. We cannot list alerts for this window — this is **not** “the DAG is down” and **not** “zero alerts”. The measurement at the origin stopped on DATE. Do not say the measurement did not run. Do not invent an empty-alert success.

When data covers the window, query `hive.datalake_data_quality.validations` (`queries.md` § DQ), team `id_dag`s, last 15 days, partition prune. Quote reserved column `"table"`.

Report two views:

1. **Open now** — latest `dt_executed` per `(id_dag, database, table, column, validation_type)` still `validation_status = 'failure'` or `table_status IN ('error', 'warning')`.
2. **Last 15 days** — distinct failing checks and days with any failure; include `consecutive_failure_days`, `validation_type`, `table_status`.

Fallback if enrich is empty but Inmetro is fresh: `datalake_inmetro_clean.data_validations` ⨝ `datalake_dag_inventory_clean.table` as in `enrich_health_metrics`.

### 6. Render — Cursor canvas (required)

The ritual **ends in a Cursor canvas**, not a markdown dump. Chat is only a short executive summary plus how to share.

1. Read `~/.cursor/skills-cursor/canvas/SKILL.md` and `sdk/index.d.ts`. Import **only** from `cursor/canvas`. Embed all data inline (no `fetch`).
2. Write **exactly one** file with the Write tool (do not only paste code in chat):

   `/Users/<user>/.cursor/projects/<workspace>/canvases/pipeline-health-<line-slug>-<YYYYMMDD>-<YYYYMMDD>.canvas.tsx`

   This workspace: `/Users/bruna.prates/.cursor/projects/Users-bruna-prates-workspace-bi-etl-ejuice/canvases/`. Do **not** `mkdir`. Do **not** commit the canvas to `bi-etl-ejuice`.
3. Default-export a component. Language of labels = user language (usually PT-BR).
4. Layout (omit a section if it has no data — never empty placeholders):

   | Block | Content |
   |-------|---------|
   | Header | `H1` time + janela BRT; `Text` secondary with sources |
   | KPIs | `Stat` grid: dias com **SLA ≥ 95%** (target do time, not 100%), pior SLA, DEI abertos, DAGs ativas |
   | Callout | Title **Resumo de SLA e incidentes** (not TLDR — the box is a full SLA recap). Covers missed-SLA / root-cause / postmortems only, not DEI, Grafana, or DQ. Detail lives in the tables below. |
   | SLA diário | `LineChart` (%); caption da fonte e janela. Table with **Causa do dia**: name the DAGs (not nicknames like "custos" or "PM"). Write “postmortem” in full + DAG. One sentence a squad member can read aloud. No YAML arrows, no flag names, no “dentro/fora” as jargon. Cascata só se a cadeia YAML + produtor atrasado já foram verificados nesse run — na célula, diga “espera X, que atrasou às HHh”. |
   | Fora de SLA | **Recorte dos piores dias** — only days from step 2c (`sla ≤ median − 5 pp`, 3–6 days, no D+1 glue). `Table` dia × SLA % do time × DAG × bucket × o que aconteceu. Caption states median + cutoff. |
   | Postmortems | `Table` or `Link` list with Drive `viewUrl` |
   | DEI | cards abertos: key, DAG, status, categoria, SLA, **atribuído** (sem Failed task; sem nota de campo deprecated) |
   | Grafana | Caption + **duas tabelas** (EMR / Databricks). CPU = tempo trabalhando, não “1 − ociosa”. Sem “preencha dag_name”. Link do dashboard em cada tabela. |
   | Data quality | open now + 15d (or Callout if lake stale) |

5. After writing, the chat **must** include:
   - A markdown link to the **absolute** `.canvas.tsx` path (canvas skill rule).
   - One-sentence exec summary (counts + própria vs cascata).
   - **How to share:** open the canvas → toolbar **Publish** → copy the URL. Teammates open it read-only in the browser ([Shared canvases](https://cursor.com/docs/agent/tools/canvas)). Paid plan + team + privacy mode that allows storage. The agent **cannot** mint that URL.
   - After a rerun, click **Publish** / **Sync** again — published snapshots do not auto-update.

Do not write CSV/JSON into the git repo. Do not substitute Google Docs, Sheets, Notion, or Confluence for the canvas.

## SLA definition (do not recompute a new formula)

Eligible DAG (denominator): `is_intraday_dag = FALSE` AND (`is_active_and_unpaused` AND NOT `is_in_ignoring_list` OR `is_special_scheduler_executed`).  
Numerator: eligible AND `is_inside_sla`.  
`sla` is that ratio × 100, one decimal (same as `fact_pipeline_metrics`).

Layer SLA hours (BRT): 08:00 default; 10:00 datamart; 12:00 reverse.

## Operational pitfalls (from live runs)

- **`execute_trino.py` JSON:** pandas date/timestamp columns crash `json.dumps`. Every date/timestamp in SELECT must be `CAST(… AS varchar)`.
- **Trino integer division:** `COUNT(...) / COUNT(...)` is bigint → 0. Use DW `sla` or `CAST(... AS DOUBLE)`.
- **Grafana names:** filter on bare DAG name, not only `bietlejuice.<name>`.
- **DEI owner:** field deprecated/empty — always intersect open cards with the team DAG inventory.
- **DQ lag:** Airflow green on `enrich_data_quality` is compatible with a hole in the table. The enrich only reads `datalake_inmetro_clean.data_validations` inside the incremental window. If both tables' last row is before the window (no partition in the window), the run writes 0 rows and succeeds. That is not “zero alerts” and not “the DAG failed”. Seen 2026-09-22: last row 2026-08-10 on source and enrich; the 2026-09-16 incremental succeeded on an empty window.
- **Postmortems:** skip Template / Copy of / Guideline. Do not ingest `PostmortemSummary` whole (multi-MB). Do not copy Owner/Contributors names into the report.
- **`dag_sla_information` duplicate rows:** the same `id_dag` × `dt_snapshot` can have one row `is_inside_sla` with `ts_first_execution_success_brt` and another `is_outside_sla` with null timestamp (seen on `jaiminho`, `rede_platform`, `robin_hood`, `ebdb_house`). Filtering `is_outside_sla = TRUE` on producers **invents** cascata externa. Collapse as in step 2.

## Failure handling

| Blocker | Action |
|---------|--------|
| Trino auth | Show the SSO URL; ask the user to login; retry once. |
| Jira MCP unauthenticated | `mcp_auth`; if it still fails, tell the user to connect Atlassian MCP. Continue without DEI. |
| Grafana empty | Try the other cluster; then dashboard URL only. |
| Unknown team | List `line_name` values; AskQuestion. |
| DQ lake stale | Report last row date on source and enrich; say the incremental succeeds on an empty window; skip the 15-day alert list. |
| Drive MCP unauthenticated | `mcp_auth`; if it still fails, continue without postmortems and say so. |
| Canvas TypeScript errors | Fix until the Write tool reports no errors; do not ship a blank canvas. |
| User wants a shareable URL | Canvas is written; they click **Publish** in the toolbar. Do not invent a `cursor.com` share URL. |

## Out of scope

- Filling or transitioning DEI cards → [`fill-incident-card`](../fill-incident-card/SKILL.md)
- Changing cluster size → [`right-size-cluster`](../right-size-cluster/SKILL.md)
- Authoring `sla/<layer>/*.yml` → [`infer-sla-expectations`](../infer-sla-expectations/SKILL.md)
- Writing to Jira, Grafana, Airflow, or the lake
- Minting the Publish URL (toolbar only — no CLI/API)
- Replacing the canvas with Docs/Sheets/Confluence as the primary report
