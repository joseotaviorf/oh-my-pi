# Tars Usage

## Ownership

**Data Owner:**
- andre.bina@quintoandar.com.br

**Data Steward:**
- aurelio.nogueira@quintoandar.com.br
- gustavo.silva@quintoandar.com.br
- luisa.frodrigues@quintoandar.com.br


---

## Overview

- **Objective:** Measure how QuintoAndar's AI data analyst (**Tars** / unstable-srat) is used — session adoption, query quality, turn latency, DataHub context attach rates, and catalog coverage gaps — so Data Ops & Governance can track the TARS Usage / Context Coverage Superset dashboard and investigate product gaps.
- **Asset status / lifecycle:** Conversation events land in S3 (`tars-logs/`) via Vector, are ingested by `tars_vector_logs` into `datalake_tars_raw.vector_logs` / `datalake_tars_clean.vector_logs`, then `enrich_tars` (daily, 06:00) builds enrich tables under `datalake_tars`. Query annotations are hybrid: Vector `trino_query` events joined best-effort to `data_platform_metrics.trino_query_complete` for `user` / `id_query`. Vector sink started **2026-08-12** — do not backfill `query_annotations` before that date (would wipe older Trino-derived history).
- **Typical actions / events:** User asks a question in Claude Code / Cursor → Tars emits Vector events (`session_start`, `trino_query`, `turn_summary` / `turn_blocked`, `turn_end`) → clean `vector_logs` → `query_annotations` / `turn_metrics` / `turn_quality` → roll-ups to `session_metrics` and URN explosion to `datahub_asset_usage` → daily product×topic coverage snapshot.
- **Common metrics:** WAU / sessions per week, DataHub attach rate (`used_datahub`), success rate (`pct_finished` / `is_success`), prompt-to-answer latency (`avg_turn_duration_ms` / `turn_metrics.duration_ms`), DQ fail / confidence (`dq_fail_count`, `avg_confidence_tier`), context depth tier (L0–L4), product coverage gaps (`is_used = false` + `expected_domain_match = true`).
- **Source systems:** Vector S3 logs (`5a-tars-prod-data` / `5a-tars-forno-forno-data`); optional Trino telemetry join (`data_platform_metrics.trino_query_complete`); DataHub product catalog seed (`schemas/datahub_products.yml` → `datahub_product_glossary`).
- **Related entities:** This is **not** Domi chatbot traffic (see [`chatbot_sessions.md`](chatbot_sessions.md) / [`evals.md`](evals.md)). It is also **not** the Conversational XP Drive-based `datalake_tars_raw.logs` table from `cross/tars_logs` — use `vector_logs` for Vector trajectory telemetry.

---

## Synonyms

| Term | Meaning | Notes |
|------|---------|-------|
| **Tars** / **TARS** / **unstable-srat** | AI data analyst skill that runs Trino for analytics | Filter source telemetry with `LOWER(source) LIKE 'tars%'` upstream; lake tables already restrict to Tars |
| **Session** / **conversa Tars** | One agent conversation | `id_session`; synthetic ids start with `no-session-` when the wire comment lacked `session_id` |
| **Synthetic session** | Single untagged query forced into a fake session | `is_synthetic_session = true` — exclude from adoption KPIs |
| **Wire comment** / **tars annotation** | `/* tars: {...} */` JSON in the SQL text | Still stamped on Trino queries; used to recover `user` / `id_query` in the hybrid join |
| **Vector event** / **trajectory log** | One flattened NDJSON line from Vector → S3 | Cleaned in `datalake_tars_clean.vector_logs`; enrich tables filter by `event_type` |
| **Turn** / **turn_end** | One user prompt → answer cycle | `turn_metrics` (latency/outcome) and `turn_quality` (`turn_summary` / `turn_blocked`) |
| **DataHub attach** / **usou DataHub** | Session/query referenced ≥1 DataHub URN | `used_datahub` (session) or `urn_count > 0` / `context_mode != 'no_datahub'` (query) |
| **Depth tier** / **contexto L0–L4** | How deep DataHub context was | L0=none, L1=datasets only, L2=1 product, L3=2 products, L4=3+ products (`depth_tier`) |
| **Coverage gap** / **produto sem uso** | Product expected for a topic but never referenced | `product_topic_coverage`: `is_used = false` AND `expected_domain_match = true` |
| **WAU** | Weekly active users of Tars | Distinct `user` over sessions in a calendar week (`session_metrics`) |
| **data_query vs debug** | Analytical SQL vs iterative error-fix SQL | `response_category` in (`data_query`, `debug`, `data_catalog`, `unknown`) |

---

## Where to query what

| You need… | Schema / table |
|-----------|----------------|
| Raw / parsed Vector events (all event types) | `datalake_tars_raw.vector_logs` / `datalake_tars_clean.vector_logs` — grain: 1 row per event; filter `event_type` |
| One row per Trino query Tars ran (question, domain, success, DataHub depth) | `datalake_tars.query_annotations` — grain: 1 row per Vector `trino_query` (hybrid Trino join); partitioned by UTC event date |
| One row per closed turn (latency, outcome, start_source) | `datalake_tars.turn_metrics` — grain: 1 row per `turn_end`; never average `duration_ms` across `start_source` |
| One row per answered / blocked turn (DQ, confidence, SQL) | `datalake_tars.turn_quality` — grain: 1 row per `turn_summary` or `turn_blocked` |
| One row per conversation (engagement, success %, DataHub flags, duration, latency) | `datalake_tars.session_metrics` — grain: 1 row per `id_session` per load day; use `dt_session` for time series |
| Which DataHub products/datasets Tars referenced | `datalake_tars.datahub_asset_usage` — grain: 1 row per (`id_query`, `datahub_urn`); filter `asset_type = 'dataProduct'` or `'dataset'` |
| Product × business-topic coverage gaps (trailing 28 days) | `datalake_tars.product_topic_coverage` — daily snapshot keyed by `dt_reference`; prefer latest `dt_reference` |
| Static catalog of DataHub Data Products (seed) | `datalake_tars.datahub_product_glossary` — full refresh; exclude `is_test = true` from gap analysis |

**Critical rules:**
- Always filter partitions with `MAKE_DATE(year, month, day)` (or `dt_session` / `dt_reference` / `dt_turn`) — tables are daily-partitioned (UTC for Vector-sourced tables).
- Exclude synthetic sessions from adoption KPIs: `is_synthetic_session = false`.
- Prefer `business_domain_normalized` over raw `business_domain` for grouping (aliases/typos are collapsed to For Rent, For Sale, Fintech, Growth, Conversational, Agents, Support and Services, Supply, Single Station, Other, unknown).
- `product_topic_coverage` is a **cross-join snapshot** of products × observed topics over ~28 days ending at `dt_reference` — do not sum `urn_hits` across many `dt_reference` days without picking one snapshot first.
- `urn_hit_count` is always `1` per row in `datahub_asset_usage` — use `SUM(urn_hit_count)` or `COUNT(*)` for hit volume.
- For turn latency, filter `start_source = 'prompt_submit'` and `trigger != 'scheduled'` before averaging `duration_ms`.
- Full SQL may also live on `turn_quality.sql` / clean `vector_logs.sql` (truncated). For engine stats, join `data_platform_metrics.trino_query_complete` by `query_id = id_query` when the hybrid join succeeded.

---

## Key Metrics

- **Weekly active users (WAU):** distinct `session_metrics.user` per calendar week of `dt_session` (exclude synthetic).
- **Sessions / queries volume:** `COUNT(DISTINCT id_session)`, `SUM(query_count)` on `session_metrics`; or `COUNT(*)` on `query_annotations`.
- **Query success rate:** `AVG(CASE WHEN is_success THEN 1.0 ELSE 0.0 END)` on `query_annotations`, or session-level `pct_finished` / `succeeded_count / query_count`.
- **DataHub attach rate (session):** share of sessions with `used_datahub = true` (or `used_data_product = true` for products only).
- **Context depth mix:** distribution of `depth_tier` / `context_mode` (`no_datahub`, `dataset_only`, `with_data_product`).
- **Debug / failure pressure:** `debug_count`, `failed_count`, and top `error_name` on failed queries.
- **Top DataHub assets:** `SUM(urn_hit_count)` by `asset_slug` / `asset_type` on `datahub_asset_usage`.
- **Catalog coverage gaps:** rows in `product_topic_coverage` where `expected_domain_match = true` AND `is_used = false` for the latest `dt_reference`.
- **Session duration:** `session_duration_min` (first to last query in the session).
- **Prompt-to-answer latency:** `AVG(duration_ms)` on `turn_metrics` where `start_source = 'prompt_submit'` and `trigger != 'scheduled'`; session roll-up `avg_turn_duration_ms`.
- **Turn completion / gaps:** `outcome` mix on `turn_metrics`; session `completed_turn_count` / `gap_turn_count`.
- **Answer DQ / confidence:** `dq_status` and `answer_confidence_tier` on `turn_quality`; session `dq_fail_count` / `avg_confidence_tier`.
- **Client mix:** breakdown by `session_source` (`claude`, `cursor`, `unknown`).

---

## Relationships with other entities

- **query_annotations → session_metrics (N:1):** many queries roll up to one `id_session`. Prefer `session_metrics` for adoption KPIs; use `query_annotations` for error/category grain.
- **turn_metrics / turn_quality → session_metrics (N:1):** turn latency and DQ roll into session-level columns (`avg_turn_duration_ms`, `gap_turn_count`, `dq_fail_count`, …).
- **query_annotations → datahub_asset_usage (1:N):** one query explodes to zero or more URN rows from `datahub_urns`. Join on `id_query` (and optionally `id_session`).
- **datahub_product_glossary → product_topic_coverage (1:N):** `product_slug` is the FK; coverage excludes `is_test = true` products at build time.
- **datahub_asset_usage → product_topic_coverage:** coverage `urn_hits` / `sessions` / `queries` aggregate product (`asset_type = 'dataProduct'`) usage over the trailing window; gaps are inferred, not direct FKs from unused products.
- **Optional bridge to raw Trino telemetry:** `query_annotations.id_query = data_platform_metrics.trino_query_complete.query_id` when the hybrid join matched and full SQL / engine stats are needed.
- **Clean Vector events:** `datalake_tars_clean.vector_logs` is the upstream of all enrich tables above (except `datahub_product_glossary`).
- **Not related to Domi evals / chatbot sessions:** do not join `datalake_chatbot.*` or Langfuse scores for Tars Trino usage.

---

## Dos and don'ts

**Do:**

- Filter `is_synthetic_session = false` when reporting WAU, sessions/week, or attach rates.
- Group domains with `business_domain_normalized` (or `dominant_business_domain` on sessions).
- For coverage gaps, fix a single `dt_reference` (usually `MAX(dt_reference)`) before ranking unused products.
- Partition-prune with `MAKE_DATE(year, month, day) BETWEEN …` on query/asset/turn tables and `dt_session` on session metrics.
- Treat `depth_tier` as ordinal (L0–L4) when measuring “how deep” context went in a session (`MAX(depth_tier)` is already baked into `session_metrics.depth_tier`).
- Split turn latency by `start_source` (and exclude `trigger = 'scheduled'`) before averaging.

**Don't:**

- Confuse Vector `vector_logs` with the Conversational XP Drive table `datalake_tars_raw.logs` — different DAG and grain.
- Average `turn_metrics.duration_ms` across mixed `start_source` values — `first_tool_call` understates true prompt-to-answer latency.
- Backfill `query_annotations` for dates before 2026-08-12 — Vector S3 has no history and would overwrite older Trino-derived rows with empties.
- Count every `product_topic_coverage` row as a “miss” — only `expected_domain_match = true AND is_used = false` are intentional gaps; unexpected domain pairs are noise.
- Use raw `business_domain` for dashboards without normalization — free text has typos and aliases.
- Assume `distinct_products` / `distinct_datasets` on `session_metrics` are true distinct counts across the session — they are `MAX(...)` of per-query counts (upper-bound proxy).
- Drop partition filters on large date ranges — `query_annotations` and `datahub_asset_usage` grow with every Tars query.

---

## Golden Queries

### Query 1 — Weekly active users and sessions (canonical adoption)

Primary KPI for Tars adoption: WAU and session volume by week, excluding synthetic sessions.

```sql
SELECT
    DATE_TRUNC('week', sm.dt_session) AS week_start,
    COUNT(DISTINCT sm.user) AS wau,
    COUNT(DISTINCT sm.id_session) AS sessions,
    SUM(sm.query_count) AS queries,
    AVG(sm.pct_finished) AS avg_pct_finished,
    AVG(CASE WHEN sm.used_datahub THEN 1.0 ELSE 0.0 END) AS datahub_attach_rate
FROM
    datalake_tars.session_metrics AS sm
WHERE
    sm.dt_session >= CURRENT_DATE - INTERVAL '56' DAY
    AND sm.is_synthetic_session = false
GROUP BY
    1
ORDER BY
    1 DESC
```

### Query 2 — Query failure mix by error and category

Investigate quality regressions at query grain.

```sql
SELECT
    qa.business_domain_normalized,
    qa.response_category,
    qa.error_name,
    COUNT(*) AS failed_queries,
    AVG(qa.execution_time_sec) AS avg_execution_time_sec
FROM
    datalake_tars.query_annotations AS qa
WHERE
    MAKE_DATE(qa.year, qa.month, qa.day) >= CURRENT_DATE - INTERVAL '28' DAY
    AND qa.is_success = false
    AND qa.is_synthetic_session = false
GROUP BY
    1,
    2,
    3
ORDER BY
    failed_queries DESC
LIMIT
    50
```

### Query 3 — DataHub context depth mix

Share of queries by `context_mode` / `depth_tier` (catalog attach quality).

```sql
SELECT
    qa.context_mode,
    qa.depth_tier,
    COUNT(*) AS queries,
    COUNT(*) * 1.0 / SUM(COUNT(*)) OVER () AS share
FROM
    datalake_tars.query_annotations AS qa
WHERE
    MAKE_DATE(qa.year, qa.month, qa.day) >= CURRENT_DATE - INTERVAL '28' DAY
    AND qa.is_synthetic_session = false
    AND qa.has_tars_comment = true
GROUP BY
    1,
    2
ORDER BY
    queries DESC
```

### Query 4 — Top DataHub Data Products referenced by Tars

Which catalog products Tars actually uses.

```sql
SELECT
    dau.asset_slug AS product_slug,
    dau.business_domain,
    COUNT(DISTINCT dau.id_session) AS sessions,
    COUNT(DISTINCT dau.id_query) AS queries,
    SUM(dau.urn_hit_count) AS urn_hits
FROM
    datalake_tars.datahub_asset_usage AS dau
WHERE
    MAKE_DATE(dau.year, dau.month, dau.day) >= CURRENT_DATE - INTERVAL '28' DAY
    AND dau.asset_type = 'dataProduct'
GROUP BY
    1,
    2
ORDER BY
    urn_hits DESC
LIMIT
    50
```

### Query 5 — Catalog coverage gaps (expected but unused products)

Products that should answer a topic but had zero Tars hits in the latest 28-day snapshot.

```sql
WITH latest AS (
    SELECT
        MAX(dt_reference) AS dt_reference
    FROM
        datalake_tars.product_topic_coverage
)
SELECT
    ptc.product_slug,
    ptc.product_name,
    ptc.datahub_domain,
    ptc.business_domain,
    ptc.urn_hits,
    ptc.sessions,
    ptc.queries
FROM
    datalake_tars.product_topic_coverage AS ptc
INNER JOIN
    latest AS l
        ON ptc.dt_reference = l.dt_reference
WHERE
    ptc.expected_domain_match = true
    AND ptc.is_used = false
ORDER BY
    ptc.business_domain,
    ptc.product_name
```

### Query 6 — Session detail for a user or domain (investigation)

Drill into recent real sessions with engagement and context flags.

```sql
SELECT
    sm.id_session,
    sm.user,
    sm.session_source,
    sm.dominant_business_domain,
    sm.query_count,
    sm.data_query_count,
    sm.debug_count,
    sm.failed_count,
    sm.pct_finished,
    sm.used_datahub,
    sm.used_data_product,
    sm.depth_tier,
    sm.session_duration_min,
    sm.dt_session,
    sm.ts_session_start,
    sm.ts_session_end
FROM
    datalake_tars.session_metrics AS sm
WHERE
    sm.dt_session >= CURRENT_DATE - INTERVAL '14' DAY
    AND sm.is_synthetic_session = false
    -- AND sm.user = 'someone@quintoandar.com.br'
    -- AND sm.dominant_business_domain = 'For Rent'
ORDER BY
    sm.ts_session_start DESC
LIMIT
    100
```

> **Note:** Date functions use Trino/Presto syntax (`DATE_TRUNC`, `INTERVAL`, `MAKE_DATE`, `CURRENT_DATE`). Adjust windows to the question. Prefer explicit columns in production dashboards instead of wide `SELECT` lists.

---

## DataHub catalog

> Added automatically by CI after merge — do not fill in manually.
