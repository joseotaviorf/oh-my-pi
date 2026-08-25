# Matias

## Overview

**Matias** is the persona name of QuintoAndar's **Dominic / D2A (Direct-to-Agent)** chatbot — the WhatsApp assistant for **1P and 3P real-estate agents**, offering informational and knowledge-base help with escalation to a human analyst when it can't resolve the request. Internal host code name is **`ian`**; in the raw chatbot lake it is **`bot = 'dominic'`**. It launched on **2026-05-04**, so there are no sessions before then. This domain (`datalake_agents_matias`) is the analytics layer built on top of those sessions.

⚠ **Matias is a chatbot, not a field agent.** It *serves* brokers but is not part of the agent-accreditation domain — for the human field agents (accreditation, hubs, revenue, tiers) see [`agents.md`](agents.md). For the generic chatbot session model shared by all bots see [`chatbot_sessions.md`](chatbot_sessions.md); for LLM-as-a-judge evaluator semantics see [`evals.md`](evals.md).

Session lifecycle: **create → AI conversation (Informational / KnowledgeBase agents, doc-search tool) → optional escalation (HumanEscalation agent → a human `analyst` takes over) → LLM-as-a-judge evaluation**. The canonical flow is `Info → KB → Info → Esc`.

The domain has two tables in `datalake_agents_matias`:
1. **`matias_session_summary`** — the analytics-ready, one-row-per-session table (**use this by default**). Every deterministic session signal is pre-computed and grouped into structs, so you never parse the nested bundle.
2. **`eval_session_bundle`** — the raw per-session bundle with the deeply-nested `conversation` / `traces` / `observations` / `evals`. Query only when you need message text, raw traces, or observation-level detail the summary doesn't expose.

**Pipeline:** `enrich_agents_matias` DAG (Spark), partitioned `year/month/day` of `session_start_ts`, merge key `id_session`. Source: `datalake_chatbot` (sessions/messages), `datalake_langfuse_clean` (traces/observations), `datalake_chatbot.evals`.

---

## Glossary and Synonyms

- **Matias** (persona), **Dominic** (system), **IAN** (host code name), **D2A / Direct-to-Agent** (product initiative) → all the same broker chatbot. Raw sessions: `datalake_chatbot.sessions.bot = 'dominic'`. Analytics: `datalake_agents_matias.matias_session_summary`.
- **Agent components** (seen as observation names, useful for reading `capability.agent_flow` and the raw bundle): host orchestration = `HostGraph` / `Host - HostPlanner` (Planner), `Moderator`, `AnswerProcessor`; sub-agents = `BrokerInformationalAssistantAgent` (→ Info), `BrokerKnowledgeBaseTaskAgent` (→ KB), `BrokerHumanEscalationAgent` (→ Esc); RAG tool = `search_broker_documents_v2`. `agent_flow` collapses the Info/KB/Esc sub-agents into an ordered path.
- **Handoff / escalação / transbordo** → a human **analyst** took over the session. Canonical signal: **`outcome.human_handoff`** (an `analyst` turn is present). Prefer this over `outcome.is_escalated_raw` (the raw `is_escalated`, which is missing/0 on partial-capture days).
- **Escalation node / escalation agent** → the `BrokerHumanEscalationAgent` ran (may evaluate and decline). `outcome.escalation_node_engaged`. Runs somewhat more often than actual handoff (includes evaluate-and-decline) and is missing on the V1-stack days (2026-06-01/02).
- **First-message escalation** → escalated on the very first user turn: `outcome.first_msg_escalation`.
- **Analyst** → the human support agent after handoff (`message_sender = 'analyst'` in the bundle). Their turns inflate raw message/duration counts — the summary separates them.
- **Doc-search** → the `search_broker_documents_v2` RAG tool. `capability.n_docsearch_calls`. **Telemetry only exists from ~2026-06-23** — scope any doc-search metric to `session_date >= DATE '2026-06-23'`.
- **Agent flow** → the collapsed ordered agent path, e.g. `"Info > KB > Info > Esc"`. `capability.agent_flow` (NULL when no agent ran).
- **Eval / evals** → LLM-as-a-judge scores (Ian* evaluators). Flattened into the `evals` struct. See [`evals.md`](evals.md).
- **Resolution** → `evals.resolution` = 1 (resolved). Convenience flag `evals.is_resolved`.
- **Partial day** → **Sundays** are truncated captures (analyst turns & `is_escalated` missing, much shorter sessions). `is_partial_day = true` — exclude from quality aggregates.
- **Low-value session** → `outcome.is_low_value` — ≤2 user messages AND avg user words < 3 (greetings / abandoned; neither resolved nor escalated).

---

## Tables

| You need... | Use this table |
|-------------|----------------|
| **Any session-level analytics** (volume, handoff, resolution, tokens, latency, tool usage, message sizes, evals) | **`datalake_agents_matias.matias_session_summary`** — one row per session, merge key `id_session`, partitioned `year/month/day`. Flat identity/time keys + 6 metric structs (below). |
| Message text, raw Langfuse traces, observation-level detail, or the full ordered conversation | `datalake_agents_matias.eval_session_bundle` — one row per session; nested `conversation` (array<struct<… traces<… observations>>>) + `evals` (map). Heavy; avoid unless you need raw content. |
| Generic cross-bot session model, message threading, bypass, queues | `datalake_chatbot.sessions` / `messages` (see [`chatbot_sessions.md`](chatbot_sessions.md)); filter `bot = 'dominic'`. |
| LLM-as-a-judge evaluator definitions & scales | `datalake_chatbot.evals` (see [`evals.md`](evals.md)). |

### `matias_session_summary` struct layout

Flat keys: `id_session` (merge key), `id_langfuse_session`, `id_copilot_session`, `user_id` (parsed from trace input; NULL for a small share of sessions), `bot`, `channel`, `active_feature_flags` (array of enabled flag names from the first Langfuse trace; NULL when missing), `session_start_ts`, `session_end_ts`, `session_date`, `weekday`, `is_weekend`, `is_partial_day`, `hour_brt`, `year`, `month`, `day`, `ts_load`.

| Struct | Fields |
|--------|--------|
| **`volume`** | `n_msgs` (all senders), `n_user_msgs`, `n_bot_msgs`, `n_analyst_msgs`, `first_user_msg_words`, `first_user_msg_chars`, `user_words_total`, `user_chars_total`, `bot_words_total`, `analyst_words_total`, `avg_user_words`, `avg_bot_words` |
| **`timing`** | `duration_sec` (full span, incl. human-agent tail), `bot_duration_sec` (user↔bot only), `first_response_latency_sec`, `avg_response_latency_sec`, `max_response_latency_sec`, `response_latencies` (array of per-turn user→bot seconds — UNNEST for the latency distribution) |
| **`cost`** | `n_llm_calls`, `total_tokens`, `prompt_tokens`, `completion_tokens`, `tokens_per_user_msg` (tokens are leaf `token_usage`; prompt-dominated) |
| **`capability`** | `n_docsearch_calls`, `n_tool_calls`, `n_agent_obs`, `n_observations`, `n_informational_obs`, `n_knowledgebase_obs`, `n_escalation_obs`, `used_informational`, `used_knowledgebase`, `agent_flow` |
| **`outcome`** | `human_handoff` (canonical), `escalation_node_engaged`, `first_msg_escalation`, `is_escalated_raw`, `is_low_value` |
| **`evals`** | `resolution` (0/1), `naturalness` (0-2), `frustration` (0-2), `ai_resistance` (0-2), `legal_risk`, `resolution_quality` (0-4), `escalation_reason`, `is_resolved`, `is_frustrated`, `has_evals` — NULL when the session was not scored |

**Critical rules:**
- **Struct access in Trino uses dot notation**: `cost.total_tokens`, `evals.resolution`, `outcome.human_handoff`. No `element_at` needed (evals are already flattened here — that's the whole point vs. the raw bundle's map).
- **Per-turn latency** lives in the `timing.response_latencies` array → `CROSS JOIN UNNEST(timing.response_latencies) AS t(latency_s)` for the distribution; per-session summaries are `timing.avg/max_response_latency_sec`.
- **Partitioned** `year/month/day` (integers) — filter those for performance, not `session_date BETWEEN`.
- **Exclude partial days** (`WHERE NOT is_partial_day`) for any quality/rate aggregate — Sundays are truncated.
- **Escalation = `outcome.human_handoff`**, not `outcome.is_escalated_raw`.

## Key Metrics

Compute these live from the current data — do not assume any fixed value.

- **Handoff rate** — `COUNT_IF(outcome.human_handoff) / COUNT(*)` (exclude partial days).
- **Resolution rate** — `COUNT_IF(evals.is_resolved) / COUNT_IF(evals.has_evals)` — over the scored subset only (non-random; over-weights low-volume days).
- **Tokens / cost** — `AVG(cost.total_tokens)`, `SUM(cost.total_tokens)` (prompt-dominated split via `prompt_tokens` vs `completion_tokens`).
- **Response latency** — `APPROX_PERCENTILE(latency_s, 0.5)` over `UNNEST(timing.response_latencies)`.
- **Sessions & users** — `COUNT(*)`, `COUNT(DISTINCT user_id)`, sessions per user.
- **Tool/agent coverage** — `COUNT_IF(capability.used_informational)`; scope doc-search to `session_date >= DATE '2026-06-23'`.
- **Agent-flow mix** — `GROUP BY capability.agent_flow`.
- **Low-value rate** — `COUNT_IF(outcome.is_low_value) / COUNT(*)`.

## Relationships with Other Entities

- **Raw chatbot session (1:1):** `matias_session_summary.id_langfuse_session = datalake_chatbot.sessions.id_langfuse_session` (or `id_session`); the raw sessions carry `bot = 'dominic'`. See [`chatbot_sessions.md`](chatbot_sessions.md).
- **Bundle (1:1):** `matias_session_summary.id_session = eval_session_bundle.id_session` — the summary is the flattened projection of the bundle.
- **Evals:** the `evals` struct is derived from `datalake_chatbot.evals` (Ian* evaluators); scale/semantics in [`evals.md`](evals.md).
- **Field agents (conceptual, NOT a join):** Matias serves brokers but is unrelated to the agent-accreditation domain — do not join to `datalake_agent_accreditation.agent`. See [`agents.md`](agents.md).

## Dos and Don'ts

**Do:**
- Default to **`matias_session_summary`**; go to `eval_session_bundle` only for raw text/traces.
- Use **`outcome.human_handoff`** as the escalation/handoff signal.
- Add **`WHERE NOT is_partial_day`** to any quality/rate metric (Sundays are truncated captures).
- Scope doc-search metrics to **`session_date >= DATE '2026-06-23'`** (telemetry start).
- Compute eval rates over **`evals.has_evals`** only, and state it's a non-random subset of sessions (not the full population).
- UNNEST **`timing.response_latencies`** for latency distributions; use `timing.bot_duration_sec` (not `duration_sec`) for bot-conversation length.
- Filter integer partitions (`year/month/day`) for performance.

**Don't:**
- Don't use `outcome.is_escalated_raw` as the escalation metric — it reads 0 on Sundays; and don't treat `escalation_node_engaged` as a handoff (it includes evaluate-and-decline and misses 2026-06-01/02).
- Don't include partial (Sunday) days in averages/rates.
- Don't compute resolution/quality rates over all sessions — only a subset are scored.
- Don't sum tokens from the raw bundle's nested observations naively — the summary already sums leaf `token_usage` (a recursive/`$.values[*]` search re-reads state-wrapper echoes and over-counts).
- Don't confuse Matias (chatbot) with the field-agent domain ([`agents.md`](agents.md)).
- Don't use `element_at()` on the summary's `evals` — it's a struct (dot access), not a map (that's the raw bundle).

## Golden Queries

### Query 1 — Daily handoff, resolution & cost (clean days)

The canonical health view: volume, human-handoff rate, scored-resolution rate, and avg tokens per day, excluding partial (Sunday) captures.

```sql
SELECT
    s.session_date,
    COUNT(*)                                                              AS sessions,
    COUNT(DISTINCT s.user_id)                                             AS users,
    ROUND(CAST(COUNT_IF(s.outcome.human_handoff) AS DOUBLE) / COUNT(*), 3) AS handoff_rate,
    ROUND(CAST(COUNT_IF(s.evals.is_resolved) AS DOUBLE)
          / NULLIF(COUNT_IF(s.evals.has_evals), 0), 3)                     AS resolution_rate_scored,
    ROUND(AVG(s.cost.total_tokens))                                        AS avg_tokens
FROM datalake_agents_matias.matias_session_summary AS s
WHERE s.session_date >= DATE '{start_date}'
  AND NOT s.is_partial_day
GROUP BY s.session_date
ORDER BY s.session_date DESC;
```

### Query 2 — Agent-flow sequences

Which orchestration paths dominate (e.g. `Info > KB > Info > Esc`).

```sql
SELECT
    COALESCE(s.capability.agent_flow, '(no agent)') AS agent_flow,
    COUNT(*)                                        AS sessions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM datalake_agents_matias.matias_session_summary AS s
WHERE s.session_date >= DATE '{start_date}'
  AND NOT s.is_partial_day
GROUP BY s.capability.agent_flow
ORDER BY sessions DESC
LIMIT 20;
```

### Query 3 — Per-turn response-latency distribution

Unnest the per-turn latency array to compute the current distribution.

```sql
SELECT
    APPROX_PERCENTILE(l.latency_s, 0.5) AS median_s,
    APPROX_PERCENTILE(l.latency_s, 0.9) AS p90_s,
    COUNT(*)                            AS bot_replies
FROM datalake_agents_matias.matias_session_summary AS s
CROSS JOIN UNNEST(s.timing.response_latencies) AS l(latency_s)
WHERE s.session_date >= DATE '{start_date}'
  AND NOT s.is_partial_day
  AND l.latency_s >= 0;
```

> **Note:** `DATE`, `COUNT_IF`, `APPROX_PERCENTILE`, and `CROSS JOIN UNNEST` follow Trino/Presto syntax. Struct fields use dot access (`s.cost.total_tokens`); adjust `{start_date}` per query.

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
