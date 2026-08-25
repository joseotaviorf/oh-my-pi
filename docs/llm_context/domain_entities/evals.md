# Evals

## Overview

Evals are **online evaluations of the Domi Platform** — LLM-as-a-judge scores produced automatically over QuintoAndar's production AI agent / chatbot sessions. Every score measures one quality or behavior dimension of a session, trace or observation — hallucination, frustration, resolution, naturalness, AI resistance, fluency, and many bot-specific dimensions. They power Domi quality dashboards and regression monitoring.

"Online" means the evaluators run against **live production traffic** (Langfuse `environment = 'default'`, `source = 'API'`), not on a curated offline test set. They do **not** score every session: a scheduled job runs **hourly** and evaluates a **sample of at most 100 sessions per run**. The lifecycle is:

1. **Session runs** — a user converses with a bot; Langfuse captures traces/observations (see `chatbot_sessions.md`).
2. **Evaluator scores the session** — an LLM-as-a-judge (or rule) emits a score with a `name`, a numeric `value`, and (for categorical scores) a `string_value` label (`datalake_langfuse_clean.scores`).
3. **Aggregation per session** — scores are rolled up into a `name -> {id, value, ts_created}` MAP, one row per Langfuse session (`datalake_chatbot.evals`).

Not every session is scored by every evaluator: each evaluator targets specific bots/flows, so a given session's `evals` MAP only contains the evaluators that ran for it. Backfilled evals **replace** previous evals for the same session.

## Glossary and Synonyms

- **Eval**, **evals** → an LLM-as-a-judge evaluation score (`datalake_chatbot.evals.evals`, `datalake_langfuse_clean.scores`)
- **Online eval** → evaluator running on live production sessions (`scores.environment = 'default'`), as opposed to offline/experimental eval runs
- **Evaluator** / **judge** → the LLM-as-a-judge (or rule) that emits a score; identified by `scores.name` (e.g. `HallucinationEvaluator`)
- **Domi** / **Domi Platform** → QuintoAndar's conversational AI platform whose sessions these evals score
- **Numeric eval** → `scores.data_type = 'NUMERIC'`; outcome encoded in `value` as a discrete category (not a continuous scale) — often binary 0/1 for event detectors (e.g. `HallucinationEvaluator` = 1 means hallucination detected), sometimes multi-valued (e.g. `NaturalnessEvaluator` 0/1/2)
- **Categorical eval** → `scores.data_type = 'CATEGORICAL'`; readable label in `string_value`, numeric encoding in `value` (e.g. `FrustrationEval` → `NO_FRUSTRATION` / `EXTERNAL_FRUSTRATION_ONLY` / `BOT_DIRECTED_FRUSTRATION`)
- **eval_host** → host/agent that produced the score, stored in the `metadata` JSON: `JSON_EXTRACT(scores.metadata, '$.eval_host')`. This is the **canonical way to scope evals to a host** — values: `wall_e`, `concierge`, `isaias`, `ian`, `sonia`, `maria`, `visits`, `matthew`, `claudia` (plus NULL when untagged). **Naming differs from `sessions.bot`** (`wall_e` vs `wall-e`; `eval_host` also exposes sub-flows like `ian`, `maria`, `claudia`, `visits` that aren't `sessions.bot` values).
- **Bot-specific eval families** → some evaluator names also carry a bot/flow prefix (`Sonia*`, `Isaias*`, `Ian*`, `Claudia*`, `Maria*`, `Matthew*`, `Offboarding*`, `Visit*`). Prefer `metadata.eval_host` over name prefixes for host scoping; use the prefix only for a specific evaluator.

## Tables

| You need... | Use this table |
|-------------|----------------|
| Individual eval scores (one row per score) — name, numeric value, categorical label, comment, value type, trace/observation linkage | `datalake_langfuse_clean.scores` (`sc`) — grain is one row per score. Join to a session via `sc.id_session = sessions.id_langfuse_session`. No partition columns; filter `ts_created` (z-ordered, **stored as VARCHAR** — compare as string `'YYYY-MM-DD...'`). |
| All evals for a session in one row (pre-aggregated) | `datalake_chatbot.evals` (`e`) — grain is one row per Langfuse session. `evals` is a `MAP<string, struct<id, value, ts_created>>` whose MAP structure is purpose-built to make per-session evals easier to **visualize and query** (one lookup by evaluator name instead of joining/pivoting the granular scores). `ts_created` is `TIMESTAMP WITH TIME ZONE`. |
| Session context (bot, channel, escalation, queues) to break evals down by | `datalake_chatbot.sessions` (`s`) — see `chatbot_sessions.md`. |
| Raw trace input/output to inspect what was scored | `datalake_langfuse_clean.traces` (`t`) — join `t.id_session = s.id_langfuse_session`, `sc.id_trace = t.id_trace`. |

**Critical rules:**
- **Deduplicate `scores`** — there can be **multiple rows per `(id_session, name)`** (re-runs, backfills). Before aggregating from `datalake_langfuse_clean.scores`, keep the latest with `ROW_NUMBER() OVER (PARTITION BY id_session, name ORDER BY CAST(ts_created AS TIMESTAMP) DESC) = 1`. The pre-aggregated `datalake_chatbot.evals` MAP already holds a single entry per evaluator name.
- **Scope to a host via `metadata.eval_host`** — `CAST(JSON_EXTRACT(scores.metadata, '$.eval_host') AS VARCHAR) = 'wall_e'` is the canonical host filter (not `sessions.bot`, whose naming differs).
- **MAP carries `value` only** — `datalake_chatbot.evals.evals` stores the numeric `value`, `id`, and `ts_created` per evaluator. It does **not** carry `string_value`. For categorical labels (e.g. `NO_FRUSTRATION`), read `datalake_langfuse_clean.scores.string_value` instead.
- **Access the MAP with `element_at`** in Trino — `element_at(evals, 'HallucinationEvaluator').value`. Never use subscript `evals['key']` (throws when the key is absent).
- **Each `value` is a per-evaluator outcome code** — e.g. `HallucinationEvaluator = 1` means hallucination detected (*bad*). The meaning of each code is evaluator-specific; look it up (and `string_value` for categorical) rather than assuming a global "higher = better" direction.
- **`scores.ts_created` and `scores.value` are VARCHAR** — `CAST(ts_created AS TIMESTAMP)` for time logic and `CAST(value AS INTEGER)` (or DOUBLE) for math. `evals.ts_created` is `TIMESTAMP WITH TIME ZONE`.
- **Online only** — these tables cover online evals (`environment = 'default'`). Offline / feature-specific eval pipelines (`datalake_text2filter_evals_raw.text2filter_evals`, `datalake_copilot_judge_metrics_raw.copilot_judge_metrics`) are out of scope for this entity.

## Key Metrics

The Wall-E quality dataset rolls individual evaluators up into a set of **session-level quality dimensions**. Each metric is `MAX(value)` over the deduplicated scores of a session, mapping one or more evaluator `name`s to a business concept:

| Metric | Evaluator `name`(s) |
|--------|---------------------|
| Resolution | `ResolutionEvaluator`, `RetentionEvaluator` |
| Frustration | `FrustrationEvaluator`, `FrustrationEval`, `DsatEvaluator` |
| Naturalness | `NaturalnessEvaluator` |
| Hallucination | `HallucinationEvaluator` |
| Hallucination (litigation) | `HallucinationLitigationEvaluator` |
| Planner / trajectory | `SessionTrajectoryEvaluator` |
| Bypass present | `SessionContainsBypassEvaluator` |
| Bypass question answered | `BypassQuestionAnsweredEvaluator` |
| Matthew agent present | `SessionContainsMatthewAgentEvaluator` |

- Compute each as `MAX(CASE WHEN name IN (...) THEN CAST(value AS INTEGER) END)` per `id_session` over the **deduplicated** scores (latest per `id_session, name`).
- Slice by host (`metadata.eval_host`), and by `bot` / `channel` / `version` after joining `datalake_chatbot.sessions`.

### Aggregating numeric evaluators — never `AVG`

The numeric `value` is a **discrete categorical encoding**, not a magnitude on a continuous scale — so `AVG(value)` is meaningless for **every** evaluator, including multi-valued ones. Each value maps to a distinct outcome (for categorical evaluators the readable label is in `string_value`; e.g. `FrustrationEval` 0/1/2 = `NO_FRUSTRATION` / `EXTERNAL_FRUSTRATION_ONLY` / `BOT_DIRECTED_FRUSTRATION`).

- **Binary (0/1) evaluators** (e.g. `HallucinationEvaluator`, `ResolutionEvaluator`, `SessionTrajectoryEvaluator`, `SessionContainsBypassEvaluator`, `*ErrorEvaluator`) → `SUM(value)` for the count of flagged sessions, or a **rate** `SUM(value) * 1.0 / COUNT(*)`.
- **Multi-valued evaluators** (e.g. `NaturalnessEvaluator` 0/1/2) → compute the **distribution**: `COUNT(*) GROUP BY value` (or share per value), or `COUNT_IF(value = N)` for one outcome. Treat each value as its own category — never average across them.
- **Always confirm the value domain first** (`SELECT DISTINCT name, value, string_value FROM scores`) before deciding how to aggregate.

Other metrics:
- Eval coverage — share of sessions scored by a given evaluator (`COUNT_IF(element_at(e.evals,'X') IS NOT NULL) / COUNT(*)`).

## Relationships with Other Entities

### Chatbot sessions (N:1 — many scores per session)

- `datalake_langfuse_clean.scores.id_session = datalake_chatbot.sessions.id_langfuse_session`
- `datalake_chatbot.evals.id_langfuse_session = datalake_chatbot.sessions.id_langfuse_session`
- Always bridge to `sessions` to break evals down by `bot`, `channel`, or `is_escalated`. Old bot (legacy) sessions have no `id_langfuse_session` and therefore no evals. See `chatbot_sessions.md`.

### Langfuse traces / observations (N:1 — scores attach to a trace or observation)

- `scores.id_trace = traces.id_trace`; `scores.id_observation = observations.id_observation`
- Use to inspect the exact LLM input/output that an evaluator scored.
- Observations also carry agent/flow signals used to flag experiments (e.g. `o.name = 'PersonalizedOpenerAgentInput'`, `'FAQAgentInputState'`, `'InformationalAssistantAgentV1Input'`) — join `traces.id_session = scores.id_session`.

### Copilot service session (1:1 — to resolve `id_user`)

- `scores.id_session = datalake_copilot_service_clean.session.id_external` exposes `id_user`, used to join user-level dimensions (e.g. `datalake_pp_multi.pp_multi_classification_history` for PP-multi owners).

### Conversation Explorer (sample, not evals)

- `datalake_conversation_explorer_clean.categorisation` carries Wall-E session *categorization* labels on a daily sample — a different signal from LLM-as-a-judge evals. Careful when mixing the two for analysis; see `conversation_explorer.md`.

## Dos and Don'ts

**Do:**
- Deduplicate `scores` to the latest per `(id_session, name)` before aggregating (`ROW_NUMBER() ... ORDER BY CAST(ts_created AS TIMESTAMP) DESC`).
- Scope to a host with `CAST(JSON_EXTRACT(scores.metadata, '$.eval_host') AS VARCHAR)` rather than `sessions.bot`.
- `CAST(value AS INTEGER)` and `CAST(ts_created AS TIMESTAMP)` — both are stored as VARCHAR in `scores`.
- Roll evaluators up to session-level metrics with `MAX(CASE WHEN name IN (...) THEN value END)` per `id_session` (see Key Metrics mapping).
- Read categorical labels from `string_value`; read numeric scores from `value`.
- Use `element_at(e.evals, 'EvaluatorName').value` for one evaluator, or `CROSS JOIN UNNEST(e.evals) AS u(eval_name, eval_struct)` to flatten all of a session's evals.
- Join through `id_langfuse_session` to `datalake_chatbot.sessions` to slice evals by `bot` / `channel` / `version`.

**Don't:**
- Don't aggregate `scores` without deduping — duplicate `(id_session, name)` rows inflate counts and averages.
- Don't equate `metadata.eval_host` with `sessions.bot` — naming differs (`wall_e` vs `wall-e`) and `eval_host` includes sub-flows (`ian`, `maria`, `claudia`, `visits`).
- Don't use MAP subscript `evals['key']` in Trino — use `element_at()`.
- Don't assume higher `value` = better — `HallucinationEvaluator`, `*ErrorEvaluator`, and other detectors use 1 = event present = worse.
- Don't `AVG` numeric evaluators — `value` is a discrete categorical encoding, not a scale. Binary 0/1 → `SUM`/rate; multi-valued (e.g. 0/1/2) → distribution per value. This holds even for "graded"-looking evaluators.
- Don't compare across evaluators on the same numeric scale — each evaluator defines its own range and meaning.
- Don't treat a missing evaluator key as a score of 0 — it means that evaluator did not run for that session.
- Don't include legacy (old bot) sessions in eval coverage denominators — they are never scored (`id_langfuse_session IS NULL`).

## Golden Queries

### Query 1 — Binary evaluator trend over time (deduplicated)

Daily count and rate for a **binary 0/1 evaluator**, keeping the latest score per session. Use `SUM`/rate (not `AVG`) for event detectors.

```sql
WITH deduped AS (
    SELECT
        sc.id_session,
        sc.name,
        CAST(sc.value AS INTEGER) AS value,
        CAST(sc.ts_created AS TIMESTAMP) AS ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY sc.id_session, sc.name
            ORDER BY CAST(sc.ts_created AS TIMESTAMP) DESC
        ) AS rn
    FROM
        hive.datalake_langfuse_clean.scores AS sc
    WHERE
        sc.ts_created >= '2026-05-01'
        AND sc.name = 'HallucinationEvaluator'
        AND sc.environment = 'default'
)
SELECT
    DATE(ts_created) AS dt_score,
    COUNT(*) AS n_sessions,
    SUM(value) AS n_hallucinations,
    SUM(value) * 1.0 / COUNT(*) AS hallucination_rate
FROM
    deduped
WHERE
    rn = 1
GROUP BY
    DATE(ts_created)
ORDER BY
    dt_score
```

### Query 2 — Binary evaluator rate by host

Resolution rate per `eval_host`, the canonical host attribution (deduplicated). `ResolutionEvaluator` is binary 0/1, so aggregate with `SUM`/rate.

```sql
WITH deduped AS (
    SELECT
        sc.id_session,
        CAST(JSON_EXTRACT(sc.metadata, '$.eval_host') AS VARCHAR) AS eval_host,
        CAST(sc.value AS INTEGER) AS value,
        ROW_NUMBER() OVER (
            PARTITION BY sc.id_session, sc.name
            ORDER BY CAST(sc.ts_created AS TIMESTAMP) DESC
        ) AS rn
    FROM
        hive.datalake_langfuse_clean.scores AS sc
    WHERE
        sc.ts_created >= '2026-05-01'
        AND sc.name = 'ResolutionEvaluator'
        AND sc.environment = 'default'
)
SELECT
    eval_host,
    COUNT(*) AS n_sessions,
    SUM(value) AS n_resolved,
    SUM(value) * 1.0 / COUNT(*) AS resolution_rate
FROM
    deduped
WHERE
    rn = 1
GROUP BY
    eval_host
ORDER BY
    resolution_rate
```

### Query 3 — Multi-valued evaluator distribution

Share of sessions per outcome for a multi-valued evaluator (`NaturalnessEvaluator` 0/1/2). Report the distribution — never `AVG`.

```sql
WITH deduped AS (
    SELECT
        sc.id_session,
        CAST(sc.value AS INTEGER) AS value,
        ROW_NUMBER() OVER (
            PARTITION BY sc.id_session, sc.name
            ORDER BY CAST(sc.ts_created AS TIMESTAMP) DESC
        ) AS rn
    FROM
        hive.datalake_langfuse_clean.scores AS sc
    WHERE
        sc.ts_created >= '2026-05-01'
        AND sc.name = 'NaturalnessEvaluator'
        AND sc.environment = 'default'
)
SELECT
    value,
    COUNT(*) AS n_sessions,
    COUNT(*) * 1.0 / SUM(COUNT(*)) OVER () AS share
FROM
    deduped
WHERE
    rn = 1
GROUP BY
    value
ORDER BY
    value
```

### Query 4 — Flatten all evals for sessions

Explode the MAP to get one row per (session, evaluator).

```sql
SELECT
    e.id_langfuse_session,
    s.bot,
    u.eval_name AS evaluator,
    u.eval_struct.value AS eval_value
FROM
    hive.datalake_chatbot.evals AS e
INNER JOIN
    hive.datalake_chatbot.sessions AS s
        ON e.id_langfuse_session = s.id_langfuse_session
CROSS JOIN
    UNNEST(e.evals) AS u(eval_name, eval_struct)
WHERE
    e.ts_created >= TIMESTAMP '2026-05-01 00:00:00 UTC'
```
