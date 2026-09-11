# Agentic Platform Metrics

## Ownership

**Data Owner:**
- lucas.cardozo@quintoandar.com.br

**Data Steward:**
- lucas.cardozo@quintoandar.com.br

## Overview

**Agentic Platform Metrics** is the family of online evaluation Health Metrics for QuintoAndar's agentic-chatbot-service. Session-level keys are binary quality and behavior rates. Trace-level keys are continuous execution metrics (latency, cost, step counts, error ratio). All of them are served from the additive daily snapshot `metric_agentic_platform.evals_daily`, keyed by `metric_key`.

The catalog is **open** for snapshot keys. New keys arrive automatically when the agentic-chatbot-service emits them on evaluation CDC events; they unpivot into `eval_metric_observations` and roll up into `evals_daily`. Treat every `metric_key` present in the snapshot as a Health Metric of this entity. Do not freeze the snapshot list as an allow-list.

**Broken UX** is a session-level **meta-metric**, not a `metric_key`. It is the OR of four calibrated component judges (repetition, technical failure, intent ignored, contradiction). Summing those four rates double-counts sessions that fire more than one judge.

The naive path averages daily rates, treats a missing `metric_key` as zero, reads Langfuse / Domi `datalake_chatbot.evals`, or reports every chatbot as the default. That is wrong: the snapshot is sparse and additive; omitted keys are not zeros; Langfuse evals are a different stack; the **default official chatbot is Mora**.

**Exists exclusively for the agentic platform (CDP `agentic_platform_*` evaluation events). This is not a For Rent or For Sale product cut. Default chatbot scope is Mora.**

## Related Domain Entities

- CDP

## Catalog

Snapshot keys below are the set already landed in the lake at authoring time. That list is **not closed**. Discover live members with `SELECT DISTINCT metric_key, grain FROM metric_agentic_platform.evals_daily`. Any additional `metric_key` that arrives through evaluation CDC is an official **Health Metric** and uses the same formulas (`grain = 'session'` → rate; `grain = 'trace'` → mean / total; percentiles from observations).

**Broken UX** is listed here as a named Health Metric but is **not** a snapshot `metric_key`. Its component set is **closed** (see Calculation) until the calibration doc changes.

| Metric | Type |
| :---- | :---- |
| Broken UX | Health Metric |
| AI Resistance | Health Metric |
| Contradiction | Health Metric |
| Frustration | Health Metric |
| Human Escalation | Health Metric |
| Intent Ignored | Health Metric |
| Persona Mismatch | Health Metric |
| Phantom Action | Health Metric |
| Repetition | Health Metric |
| Resolution | Health Metric |
| Technical Failure | Health Metric |
| Trace Cost | Health Metric |
| Trace Error Step Ratio | Health Metric |
| Trace Latency | Health Metric |
| Trace Step Count | Health Metric |
| Trace Tool Call Count | Health Metric |

## Glossary and Synonyms

- **Agentic Platform Metrics**, **métricas da plataforma agentic**, **evals_daily**, **metric_agentic_platform** → this entity
- **Broken UX**, **broken UX**, **broken_ux**, **Broken UX umbrella**, **UX quebrada** → Broken UX (session OR of four component judges; not a `metric_key`)
- **Mora**, **mora**, **mora_chatbot**, **mora_chatbot_whatsapp**, **Mora chatbot**, **Mora WhatsApp** → the default official chatbot. Canonical `id_chatbot` values: `'mora'`, `'mora_chatbot'`, `'mora_chatbot_whatsapp'`
- **Resolution**, **resolução**, **resolutividade**, `metric_key = 'resolution'` → Resolution
- **Human Escalation**, **escalação humana**, **handoff humano**, `human_escalation` → Human Escalation
- **AI Resistance**, **resistência à IA**, `ai_resistance` → AI Resistance
- **Contradiction**, **contradição**, `contradiction` → Contradiction
- **Frustration**, **frustração**, `frustration` → Frustration
- **Intent Ignored**, **intent ignorado**, `intent_ignored` → Intent Ignored
- **Persona Mismatch**, **persona incorreta**, `persona_mismatch` → Persona Mismatch
- **Phantom Action**, **ação fantasma**, `phantom_action` → Phantom Action
- **Repetition**, **repetição**, `repetition` → Repetition
- **Technical Failure**, **falha técnica**, `technical_failure` → Technical Failure
- **Trace Cost**, **custo de trace**, `trace_cost` → Trace Cost (USD)
- **Trace Latency**, **latência de trace**, `trace_latency` → Trace Latency (seconds)
- **Trace Error Step Ratio**, `trace_error_step_ratio` → Trace Error Step Ratio
- **Trace Step Count**, `trace_step_count` → Trace Step Count
- **Trace Tool Call Count**, `trace_tool_call_count` → Trace Tool Call Count
- **Evals**, **online evals**, **Langfuse scores**, **Domi evals**, **datalake_chatbot.evals** → near-miss — Langfuse/Domi sampled judges, not this CDP agentic snapshot
- **Conversation Explorer**, **CE** → near-miss — Wall-E sampled categorisation, not a census of agentic evals
- **Chatbot sessions**, **Sauron sessions**, **datalake_chatbot.sessions** → near-miss — legacy/bot session census; evaluation `id_session` here is the judged window, not the CDC platform session
- **Wall-E escalation rate** → near-miss — a different official metric family

## Scope

**Included**: CDP evaluation events `agentic_platform_session_evaluation` and `agentic_platform_trace_evaluation` after collapse into `eval_metric_observations` and additive rollup into `evals_daily`. Default official numbers: Mora (`id_chatbot IN ('mora', 'mora_chatbot', 'mora_chatbot_whatsapp')`). Session grain → binary rate formula. Trace grain → mean / total (percentiles from observations). Every `metric_key` that CDC lands in the snapshot, including keys that appear after this document was written. **Broken UX**: session-eval universe for Mora in the window; a session counts if any of `repetition`, `technical_failure`, `intent_ignored`, `contradiction` has `metric_value >= 1`.

**Excluded**: For Rent / For Sale product cuts; Langfuse / Domi online evals (`datalake_chatbot.evals`, `datalake_langfuse_clean.scores`); Conversation Explorer samples; CDC platform-session lifecycle tables as the eval denominator (`datalake_agentic_platform_clean.sessions`); non-Mora chatbots in the **default** official number (include them only when the question names that chatbot); `__UNKNOWN__` on `id_chatbot` and on a dimension being used as a slice; imputing zeros for a `metric_key` that did not emit in the window; folding other session keys (`frustration`, `phantom_action`, `ai_resistance`, `human_escalation`, `persona_mismatch`, `resolution`, …) into Broken UX; treating Broken UX as a row in `evals_daily`.

## Calculation

Session Health Metrics are binary rates. Trace Health Metrics are re-aggregated totals or means. Percentiles are not stored in the snapshot. Pick the formula from `grain`, not from a hardcoded key list. **Broken UX** is computed at session grain from observations, not from `evals_daily`.

The correct calculation is:

```
session_rate(key) = SUM(cnt_positive) / SUM(cnt_observations)
    for grain = 'session' and metric_key = key

trace_mean(key) = SUM(sum_value) / SUM(cnt_observations)
    for grain = 'trace' and metric_key = key

trace_total(key) = SUM(sum_value)
    for grain = 'trace' (use this for Trace Cost in USD)

trace_percentile(key, p) = approx_percentile(metric_value, p)
    from datalake_agentic_platform.eval_metric_observations
    for eval_level = 'trace'

broken_ux_rate = COUNT(DISTINCT sessions with any component fired)
    / COUNT(DISTINCT session-eval sessions)
    component fired ⇔ metric_key IN (
        'repetition',
        'technical_failure',
        'intent_ignored',
        'contradiction'
    )
    AND metric_value >= 1
```

where `cnt_positive` counts collapsed observations with `metric_value >= 1` (numerator for binaries; unused for continuous keys), `cnt_observations` is the denominator, and `sum_value` is the sum of `metric_value` (USD for `trace_cost`; equals `cnt_positive` for binaries). Lake encoding for the Broken UX components is `1.0` = judge fired (problem present), `0.0` = clean.

Averaging daily rates (or averaging `metric_value` across mixed keys) weights days and chatbots incorrectly. A missing `metric_key` in the window is coverage gap, not a zero. A key that is not in the Catalog table but exists in the snapshot is still in this entity. Summing the four Broken UX component rates (or taking `MAX` of those rates) is not the umbrella: sessions can fire more than one judge.

### Canonical Filter

Apply on `metric_agentic_platform.evals_daily` for the **default official number**:

```sql
id_chatbot IN ('mora', 'mora_chatbot', 'mora_chatbot_whatsapp')
AND CAST(dt AS DATE) >= DATE '2026-09-01'
AND CAST(dt AS DATE) < DATE '2026-10-01'
AND grain = 'session'   -- session family
-- OR grain = 'trace'   -- trace family
AND metric_key = '<key>'  -- omit to return every key in the family
```

When the question names another chatbot, replace the Mora `IN` list with that `id_chatbot`. When slicing by `channel`, `session_outcome`, `topic`, or `agent_declared`, also exclude that column's `'__UNKNOWN__'`.

**Warning**: Omitting the Mora predicate and keeping only `id_chatbot <> '__UNKNOWN__'` mixes every chatbot that later lands in the snapshot into the default number. Applying `session_outcome <> '__UNKNOWN__'` or `topic <> '__UNKNOWN__'` on `grain = 'trace'` drops every trace row — those columns are the sentinel by design on traces. Restricting SQL to the Catalog table's snapshot keys hides CDC keys that arrived later. Slicing session rates by `agent_declared` attributes a conversation-level judge to one agent and is not the official session number. Computing Broken UX from `evals_daily` (sum, max, or average of the four `metric_key` rates) double-counts multi-flag sessions and is not the official umbrella.

### Nuances

No external weight or parameter table. Read additive columns from `metric_agentic_platform.evals_daily` at query time. Catalog types for `dt`, `cnt_observations`, `cnt_positive`, and `sum_value` are VARCHAR — `CAST` before math and date predicates.

| Column | Description |
| :---- | :---- |
| `metric_key` | Sparse KPI identifier, open set via evaluation CDC. Filter to one key when asked; omitted keys are not zeros. Broken UX is not a key. |
| `grain` | `session` → binary rate; `trace` → mean / total. Named `grain` in the snapshot (`eval_level` upstream). |
| `id_chatbot` | Default official values: `'mora'`, `'mora_chatbot'`, `'mora_chatbot_whatsapp'`. Lake at authoring had `mora_chatbot` and `mora_chatbot_whatsapp`; keep `'mora'` in the predicate for CDC. |
| `__UNKNOWN__` | Merge sentinel for absent dimension values. Do not use it as a substitute for the Mora filter. Exclude other dimensions only when slicing by them. |
| `cnt_positive` | Count of observations with `metric_value >= 1`. Session-rate numerator. For Broken UX components, `1.0` means the judge fired. |
| `sum_value` | Sum of `metric_value`. Trace Cost total USD; binaries equal `cnt_positive`. |
| `agent_declared` | Valid slice for trace metrics. Lineage-only for session metrics — do not split session rates by it. |
| Broken UX components | Closed set: `repetition`, `technical_failure`, `intent_ignored`, `contradiction`. Calibration: [Broken UX & Resolution: Metric Calibration](https://docs.google.com/document/d/15_PtJUHihtJqVEAU_vcrcY7f5efKWSSwmvkJU72cjiU/edit). New CDC keys do **not** join this OR until that contract changes. |

**Join key**: none. Parameters are not joined. Map a named metric to `metric_key` via Glossary, or to whatever key CDC landed (`DISTINCT metric_key`).

**Fallback**: if a `metric_key` has no rows in the window, report no coverage. Do not fill zeros. Percentiles have no additive encoding — read `datalake_agentic_platform.eval_metric_observations` (already collapsed: latest `(id_session, metric_key)` for session, latest `(id_trace, agent_declared, metric_key)` for trace). Evaluation `id_session` is the judged window, not `datalake_agentic_platform_clean.sessions.id_session`. Broken UX denominator is distinct `id_session` in the Mora session-eval universe for the window (any session-level observation); a session with none of the four component keys present counts as not-broken, not as missing coverage.

## Dos and Don'ts

**Do:**

- Default official numbers to Mora: `id_chatbot IN ('mora', 'mora_chatbot', 'mora_chatbot_whatsapp')`
- Discover snapshot keys with `DISTINCT metric_key, grain` — new CDC keys are in this entity
- Re-aggregate with `SUM(cnt_positive)` / `SUM(cnt_observations)` (session) or `SUM(sum_value)` / `SUM(cnt_observations)` (trace mean)
- Compute Broken UX as a session-level OR on `eval_metric_observations`, then divide by distinct session-eval sessions
- Read percentiles from `eval_metric_observations`, never from `evals_daily`
- Treat a missing `metric_key` as no coverage

**Don't:**

- Treat the Catalog table as a closed allow-list for snapshot keys
- Report all chatbots as the default official number
- Average daily rates or pool all `metric_key` values into one number
- Compute these KPIs from Langfuse / Domi evals or Conversation Explorer
- Slice session-level rates by `agent_declared`
- Filter trace rows on `session_outcome` or `topic` sentinels
- Impute zero for a key that did not emit
- Sum or average the four Broken UX component rates, or look for `metric_key = 'broken_ux'` in `evals_daily`
- Add new CDC session keys to the Broken UX OR without an update to the calibration contract

## Golden Queries

Default official **session** Health Metrics for Mora in a calendar month. The query returns every session `metric_key` currently in the snapshot (CDC-open). Replace the date window as needed. `CAST` is required because snapshot additive columns are VARCHAR in the catalog.

```sql
SELECT
    metric_key,
    SUM(CAST(cnt_positive AS DOUBLE)) * 1.0
        / NULLIF(SUM(CAST(cnt_observations AS DOUBLE)), 0) AS session_rate
FROM metric_agentic_platform.evals_daily
WHERE grain = 'session'
    AND id_chatbot IN ('mora', 'mora_chatbot', 'mora_chatbot_whatsapp')
    AND CAST(dt AS DATE) >= DATE '2026-09-01'
    AND CAST(dt AS DATE) < DATE '2026-10-01'
GROUP BY
    metric_key
ORDER BY
    metric_key
```

Default official **trace** Health Metrics for Mora in the same window. `total_value` is the official total (Trace Cost in USD); `mean_value` is the official mean. New trace keys from CDC appear as extra rows.

```sql
SELECT
    metric_key,
    SUM(CAST(sum_value AS DOUBLE)) AS total_value,
    SUM(CAST(sum_value AS DOUBLE)) * 1.0
        / NULLIF(SUM(CAST(cnt_observations AS DOUBLE)), 0) AS mean_value
FROM metric_agentic_platform.evals_daily
WHERE grain = 'trace'
    AND id_chatbot IN ('mora', 'mora_chatbot', 'mora_chatbot_whatsapp')
    AND CAST(dt AS DATE) >= DATE '2026-09-01'
    AND CAST(dt AS DATE) < DATE '2026-10-01'
GROUP BY
    metric_key
ORDER BY
    metric_key
```

Trace percentiles for Mora. This is the only supported percentile path — `evals_daily` cannot reconstruct a distribution. New trace keys from CDC appear as extra rows.

```sql
SELECT
    metric_key,
    approx_percentile(CAST(metric_value AS DOUBLE), 0.5) AS p50,
    approx_percentile(CAST(metric_value AS DOUBLE), 0.95) AS p95
FROM datalake_agentic_platform.eval_metric_observations
WHERE eval_level = 'trace'
    AND id_chatbot IN ('mora', 'mora_chatbot', 'mora_chatbot_whatsapp')
    AND CAST(ts_event AS TIMESTAMP) >= TIMESTAMP '2026-09-01 00:00:00'
    AND CAST(ts_event AS TIMESTAMP) < TIMESTAMP '2026-10-01 00:00:00'
GROUP BY
    metric_key
ORDER BY
    metric_key
```

Default official **Broken UX** for Mora in the same window. Session-eval universe in the denominator; numerator is distinct sessions where any of the four component judges fired (`metric_value >= 1`). Do not read this from `evals_daily`.

```sql
WITH session_universe AS (
    SELECT DISTINCT
        id_session
    FROM datalake_agentic_platform.eval_metric_observations
    WHERE eval_level = 'session'
        AND id_chatbot IN ('mora', 'mora_chatbot', 'mora_chatbot_whatsapp')
        AND CAST(ts_event AS TIMESTAMP) >= TIMESTAMP '2026-09-01 00:00:00'
        AND CAST(ts_event AS TIMESTAMP) < TIMESTAMP '2026-10-01 00:00:00'
),
broken AS (
    SELECT DISTINCT
        id_session
    FROM datalake_agentic_platform.eval_metric_observations
    WHERE eval_level = 'session'
        AND id_chatbot IN ('mora', 'mora_chatbot', 'mora_chatbot_whatsapp')
        AND metric_key IN (
            'repetition',
            'technical_failure',
            'intent_ignored',
            'contradiction'
        )
        AND CAST(metric_value AS DOUBLE) >= 1
        AND CAST(ts_event AS TIMESTAMP) >= TIMESTAMP '2026-09-01 00:00:00'
        AND CAST(ts_event AS TIMESTAMP) < TIMESTAMP '2026-10-01 00:00:00'
)
SELECT
    COUNT(*) AS cnt_sessions,
    SUM(
        CASE
            WHEN b.id_session IS NOT NULL THEN 1
            ELSE 0
        END
    ) AS cnt_broken_ux,
    SUM(
        CASE
            WHEN b.id_session IS NOT NULL THEN 1
            ELSE 0
        END
    ) * 1.0 / NULLIF(COUNT(*), 0) AS broken_ux_rate
FROM session_universe AS su
LEFT JOIN broken AS b
    ON su.id_session = b.id_session
```
