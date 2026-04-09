# Chatbot Sessions

## Overview

A chatbot session represents a conversation between a user and one of QuintoAndar's AI agents (bots/hosts) through WhatsApp or in-app channels. Sessions are orchestrated by Sauron and executed by Copilot Service, with LLM observability captured in Langfuse. The domain covers session lifecycle, message threading, LLM evaluation scores, pre-bot bypasses, and escalation to human support.

The lifecycle typically includes:
1. **Session creation** — user contacts QuintoAndar through a channel, for WhatsApp, different phone numbers host different bots.
2. **AI conversation** — the bot handles the user's request, generating messages and LLM traces (`messages.conversation_type = 'HUMAN-AI'`)
3. **Bypass check** — pre-bot rules may route the user directly to a queue before the bot engages (`bypass.bypass`).
4. **Escalation** — the bot hands off to a human analyst either by detecting it can't solve an issue or by explicit request of the user (`sessions.is_escalated`)
5. **Human conversation** (if escalated) — an analyst takes over the session (`messages.conversation_type = 'HUMAN-HUMAN'`)
6. **Evaluation** — LLM-as-a-judge scores assess session quality and multiple dimensions of AI performance (`evals.evals`)

Not all sessions follow every step. Some are bypassed entirely (pre-bot routing), some are resolved fully by the AI, and legacy sessions (Greenseer) lack Langfuse observability. There should be a very low and neglectible number of legacy sessions (`bot = 'old bot'`).

## Glossary and Synonyms

- **Sessão de chatbot**, **conversa**, **atendimento bot** → `chatbot session` (`datalake_chatbot.sessions`)
- **Host**, **bot**, **agente** → the AI persona handling the session (`sessions.bot`): sonia, wall-e, isaias, matthew, concierge, copilot, vandinha, old bot. There could be an overlap of concepts here as 'agente' can sometimes refer to a host, like wall-e, but can also refer to an specific AI Agent/sub-agent called within a host, e.g. `HumanEscalationAgent`.
- **Sonia** → rent-focused WhatsApp bot. Filter: `sessions.bot = 'sonia'`
- **Wall-E** → support bot (in-app and WhatsApp). Filter: `sessions.bot = 'wall-e'`
- **Isaias** → landlord lead qualification bot. Filter: `sessions.bot = 'isaias'`. Funnel flags in `isaias_conversational_flow`
- **Matthew** → collections-related WhatsApp bot. Filter: `sessions.bot = 'matthew'`
- **Concierge** → demand/search concierge bot. Filter: `sessions.bot = 'concierge'`
- **Vandinha** → for-sale transaction EOP bot. Filter: `sessions.bot = 'vandinha'`
- **Old bot** → legacy Greenseer sessions. Filter: `sessions.bot = 'old bot'`. No  `id_langfuse_session`.
- **Escalação**, **transbordo**, **escalation** → escalation to human analyst (`sessions.is_escalated = true`). **Transbordo** is somewhat of an old name, curent business terminology revolves around **escalation**.
- **Bypass** → pre-bot action that routes the user to a queue before AI engagement (`bypass.bypass`)
- **Eval**, **evals** → LLM-as-a-judge evaluation score (`evals.evals`)
- **SPOC** → excluded from `messages` table
- **Fila**, **departamento** (queue) → support queue/department the session is routed to (`sessions.first_queue`, `sessions.last_queue`)

## Tables

| You need... | Use this table |
|-------------|----------------|
| Session-level data (bot, channel, status, escalation, queues) | `datalake_chatbot.sessions` (`s`) — one row per session, merge key `id_sauron_session`. Legacy (old bot) rows have `id_langfuse_session` as NULL. |
| Message-level data (text, role, timing, conversation type) | `datalake_chatbot.messages` (`m`) — one row per message, merge key `id_message`. Excludes SPOC sessions. |
| LLM evaluation scores | `datalake_chatbot.evals` (`e`) — one row per Langfuse session. `evals` is a MAP column; use `element_at()` in Trino or UNNEST. |
| Pre-bot bypass | `datalake_chatbot.bypass` (`b`) — one row per bypass per session. Includes `inside_sales_bypass` from observations. |
| Isaias lead qualification funnel | `datalake_chatbot.isaias_conversational_flow` (`icf`) — one row per Langfuse session with boolean flags for each qualification step. |
| Raw LLM traces (latency, model, input/output) | `datalake_langfuse_clean.traces` (`t`) — one row per trace. JOIN to sessions via `t.id_session = s.id_langfuse_session`. |
| LLM span/generation details (model, tokens, cost), specific sub agent or tool calling | `datalake_langfuse_clean.observations` (`o`) — one row per observation. JOIN via `o.id_trace = t.id_trace`. Filter specific observations for exact sub agent or tool via `o.name`|

**Critical rules:**
- **Three session IDs**: `id_sauron_session` (always present — stable key), `id_session` (Copilot, NULL for old bot), `id_langfuse_session` (Langfuse, NULL for old bot). Prefer JOIN through `id_langfuse_session` for session-level analysis, fallback to `id_sauron_session` if `id_langfuse_session` is missing in the table, e.g. `datalake_chatbot.messages`
- **Evals MAP access**: in Trino, use `element_at(evals, 'score_name').value` for a specific score, or `CROSS JOIN UNNEST(evals) AS t(eval_name, eval_struct)` to flatten all scores.
- **No partition columns** on `datalake_chatbot` tables — filter on `ts_created` for performance (z-ordered).
- - **No partition columns** on `datalake_langfuse_clean` tables — filter on `ts_created` or `ts_started` for performance (z-ordered).

## Key Metrics

- Session volume per day/week/month (count of `sessions.id_sauron_session`, filter by `sessions.ts_created`)
- Escalation rate (`COUNT_IF(is_escalated) / COUNT(*)` on `sessions`)
- Escalation error rate (`COUNT_IF(is_escalated AND first_queue != last_queue) / COUNT_IF(is_escalated)` on `sessions`)
- Breakdown of metrics by bot (`sessions.bot`) and channel (`sessions.channel`)
- AI response time (`messages.reply_time` where `role = 'AI'`)
- LLM-as-a-judge scores (individual scores from `element_at(evals.evals, '{score_name}').value`)
- Isaias funnel conversion (sequential `has_*_success` flags in `isaias_conversational_flow`)
- Bypass rate (`COUNT` of `bypass` rows / total sessions)
- Bot version distribution (`sessions.version` from Langfuse traces)

## Relationships with Other Entities

### Messages (1:N — one session has many messages)

- `sessions.id_sauron_session = messages.id_sauron_session`
- Messages already exclude SPOC sessions

### Evals (1:1 — one eval row per Langfuse session)

- `sessions.id_langfuse_session = evals.id_langfuse_session`
- Only available for non-legacy sessions (where `id_langfuse_session IS NOT NULL`)

### Bypass (1:N — one session may have multiple bypasses)

- `sessions.id_langfuse_session = bypass.id_langfuse_session`
- Only available for non-legacy sessions

### Isaias Conversational Flow (1:1 — one flow record per Langfuse session)

- `sessions.id_langfuse_session = isaias_conversational_flow.id_langfuse_session`
- Only relevant when `sessions.bot = 'isaias'`

### Langfuse Traces (1:N — one session has many traces)

- `sessions.id_langfuse_session = traces.id_session`
- Traces contain LLM input/output, model name, environment, tags

### Langfuse Observations (N:1 to trace — many observations per trace)

- `observations.id_trace = traces.id_trace`
- Observations contain model parameters, token usage (`usage_details`), cost (`cost_details`), latency (`ts_started` / `ts_ended`)

### Langfuse Scores (N:1 to session — many scores per session)

- `scores.id_session = sessions.id_langfuse_session`
- Individual score records before MAP aggregation in `evals`

### Support Tickets (1:1 — latest ticket per session)

- `sessions.id_ticket` links to `datalake_customer_support.tickets.id_ticket`
- Only populated when `sessions.is_escalated = true`

## Dos and Don'ts

**Do:**
- Use `datalake_chatbot.sessions` as the starting point for session-level analysis — it unifies orchestrator (Copilot) and legacy (Greenseer) paths
- Prefer JOIN through `id_langfuse_session` for session-level analysis, fallback to `id_sauron_session` if `id_langfuse_session` is missing in the table, e.g. `datalake_chatbot.messages`
- Use `id_langfuse_session` when joining to `evals`, `bypass`, `isaias_conversational_flow`, or `datalake_langfuse_clean` tables
- Filter `sessions.bot` to scope analysis to a specific AI agent (e.g., `bot = 'isaias'` for landlord lead qualification)
- Use `element_at(evals, 'score_name')` in Trino to safely access MAP entries (returns NULL if key is missing)
- Filter on `ts_created` for time-based queries — tables are z-ordered on this column

**Don't:**
- Don't use `id_session` as the universal session key — it is NULL for all legacy (old bot) sessions. Use `id_sauron_session` instead.
- Don't forget to exclude old bot sessions when analyzing Langfuse-dependent data: `WHERE id_langfuse_session IS NOT NULL`
- Don't use MAP subscript syntax (`evals['key']`) in Trino — it throws an error if the key doesn't exist. Use `element_at()` instead.
- Don't assume `messages` contains all sessions — SPOC sessions are filtered out
- Don't confuse `first_queue` (escalation queue from Langfuse observations) with Sauron `department` — the enriched `sessions.first_queue` reflects the actual escalation target, not the initial routing
- Don't join `messages` to `evals` directly — they use different session ID types (`id_sauron_session` vs `id_langfuse_session`). Go through `sessions` to bridge them.

## Golden Queries

### Query 1 — Session volume by bot and channel

Daily session counts broken down by bot persona and communication channel.

```sql
SELECT
    DATE(s.ts_created) AS dt_session,
    s.bot,
    s.channel,
    COUNT(*) AS total_sessions,
    COUNT_IF(s.is_escalated) AS escalated_sessions,
    ROUND(CAST(COUNT_IF(s.is_escalated) AS DOUBLE) / COUNT(*), 2) AS escalation_rate
FROM
    datalake_chatbot.sessions AS s
WHERE
    s.ts_created >= TIMESTAMP '{start_date}'
    AND s.ts_created < TIMESTAMP '{end_date}'
GROUP BY
    DATE(s.ts_created),
    s.bot,
    s.channel
ORDER BY
    dt_session DESC,
    total_sessions DESC
```

### Query 2 — Escalation error rate

Sessions that were escalated to the wrong human support queue.

```sql
SELECT
    s.bot,
    s.first_queue,
    s.last_queue,
    COUNT_IF(s.first_queue != s.last_queue) AS escalated_error,
    ROUND(COUNT_IF(s.first_queue != s.last_queue) / CAST(COUNT_IF(s.is_escalated) AS DOUBLE), 2)
FROM
    datalake_chatbot.sessions AS s
WHERE
    s.ts_created >= TIMESTAMP '{start_date}'
    AND s.ts_created < TIMESTAMP '{end_date}'
    AND s.is_escalated = true
GROUP BY
    s.bot,
    s.first_queue,
    s.last_queue
ORDER BY
    escalated_sessions DESC
```