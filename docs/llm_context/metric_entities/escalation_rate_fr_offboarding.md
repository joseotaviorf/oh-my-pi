# Escalation Rate FR Offboarding

## Ownership

**Data Owner:**

- [isis.rocha@quintoandar.com.br](mailto:isis.rocha@quintoandar.com.br)

**Data Steward:**

- [lira.maria@quintoandar.com.br](mailto:lira.maria@quintoandar.com.br)

## Overview

**Escalation Rate** is the share of Offboarding Agent (For Rent) sessions that were escalated to a human agent. The metric measures — per day —, what proportion of sessions started with the bot required human intervention in the rental flow.

**This metric exists exclusively for the For Rent offboarding agent (`ForRentOffboardingAgentV1`).**

## Related Business Entities

- Chatbot Sessions

## MBR

- Post Contract

## Glossary and Synonyms

- **Escalation Rate**, **Escalation Rate FR Offboarding**, **taxa de escalonamento** → this metric

## Scope

**Included**: sessions tagged `wall_e` in traces, joined with observations from the `ForRentOffboardingAgentV1` agent, joined with `datalake_chatbot.sessions` for `is_escalated`, restricted to the requested analysis window (session-day grain).

**Excluded**: sessions from other agents/bots, sessions with no match in the chatbot sessions table, periods outside the configured analysis window.

## Calculation

The canonical query returns raw counts by `is_escalated` (`true`/`false`) — the percentage calculation is done at the visualization layer (e.g., Superset), not inside the SQL. There is no weighted aggregation — it's a direct pool of sessions.

The metric aggregates unique sessions (`COUNT(DISTINCT id_session)`) segmented by the `is_escalated` field from the `datalake_chatbot.sessions` table. The escalation numerator is the count of sessions where `is_escalated = true`; the denominator is the total number of sessions in the period.

The correct calculation is:

```
Escalation Rate (%) = COUNT(DISTINCT id_session WHERE is_escalated = true)
                       / COUNT(DISTINCT id_session) × 100
```

where the numerator is the count of unique sessions with `is_escalated = true`, and the denominator is the total number of unique sessions in the period.

### Canonical Filter

Apply on `datalake_langfuse_clean.traces`, `datalake_langfuse_clean.observations`, and `datalake_chatbot.sessions` (mandatory JOIN — `is_escalated` lives only on `sessions`, see Join key below):

```sql
-- Traces filter: only wall_e agent sessions
WHERE contains(tags, 'wall_e')

-- Observations filter: only the FR offboarding agent
WHERE name IN ('ForRentOffboardingAgentV1')

-- Mandatory JOIN to bring in is_escalated (see Nuances → Join key)
LEFT JOIN datalake_chatbot.sessions
    ON CAST(traces.id_session AS VARCHAR) = CAST(sessions.id_langfuse_session AS VARCHAR)

-- Mandatory period bound at session-day grain (see Nuances → Grain), set to the
-- requested analysis window — never hardcode
WHERE ts_created >= TIMESTAMP '{window_start}'
  AND ts_created <  TIMESTAMP '{window_end}'
```

**Warning**: dropping the `wall_e` tag filter on `traces` pulls in sessions outside the product's scope; dropping the `ForRentOffboardingAgentV1` filter on `observations` includes sessions from other agents, inflating both the numerator and denominator with unrelated volume. Omitting the `LEFT JOIN` to `datalake_chatbot.sessions` leaves `is_escalated` unavailable, making the rate incomputable; omitting the period bound pools the entire table history instead of the requested analysis window, silently changing the denominator.

### Nuances

`is_escalated` is a boolean column in `datalake_chatbot.sessions`. The JOIN with traces uses `CAST(id_session AS VARCHAR) = CAST(id_langfuse_session AS VARCHAR)` for type compatibility.

| Column | Description |
| :---- | :---- |
| `is_escalated` | Boolean escalation flag from `datalake_chatbot.sessions` — the segmentation field for both the numerator (`= true`) and denominator (all sessions) of the rate. |
| `recontact_max` | A field computed in the base subquery via `MAX(...) OVER (PARTITION BY id_user)`. Indicates whether the user had recontact sessions within a 48h window. Available for slicing, but does not enter the Escalation Rate calculation. |
| Scores (`s1`, `s2`) | The base joins scores by `id_trace` and by `id_session` via `COALESCE`. Scores are available for qualitative analysis but do not impact the rate's numerator or denominator. |

**Grain**: session-day. A single `id_session` can have multiple messages — deduplication is guaranteed by `COUNT(DISTINCT id_session)`.

**Join key**: `CAST(id_session AS VARCHAR) = CAST(id_langfuse_session AS VARCHAR)` between `datalake_langfuse_clean.traces` and `datalake_chatbot.sessions`.

**Fallback**: not applicable — sessions with no match in `datalake_chatbot.sessions` are excluded from scope (see Scope → Excluded).

### Tables Involved

| Table | Role |
| :---- | :---- |
| `datalake_langfuse_clean.traces` | Session source; filtered by `wall_e` tag |
| `datalake_langfuse_clean.observations` | Filter by the `ForRentOffboardingAgentV1` agent |
| `datalake_langfuse_clean.scores` | Quality scores per trace and per session (informational) |
| `datalake_chatbot.sessions` | Source of `is_escalated`, `first_queue`, `last_queue`, `channel` |
| `datalake_copilot_service_clean.message` | Session messages; role and timestamps for flow analysis |

## Dos and Don'ts

**Do:**

- Filter traces by `contains(tags, 'wall_e')` — required to isolate the correct agent
- Filter observations by `name IN ('ForRentOffboardingAgentV1')` — required for the FR offboarding scope
- Use `COUNT(DISTINCT id_session)` — sessions, not traces or messages
- Do `CAST(... AS VARCHAR)` on both sides of the JOIN between `id_session` and `id_langfuse_session`

**Don't:**

- Don't use `COUNT(*)` directly — duplicates from messages/scores would inflate the total
- Don't remove the observations filter — it would include sessions from other agents
- Don't remove the `wall_e` tag — it would include sessions outside the product's scope
- Don't calculate the percentage inside Trino with integer division — cast to `DOUBLE` or calculate it at the BI layer

## Golden Queries

Canonical query for daily session volume segmented by escalation status. The traces/observations/sessions JOIN pattern follows `business_entities/chatbot_sessions.md`; what is exclusive to this metric is the `wall_e` + `ForRentOffboardingAgentV1` filter combination and the `is_escalated` segmentation.

```sql
SELECT
    date_trunc('day', CAST(ts_created AS TIMESTAMP)) AS ts_created,
    is_escalated,
    COUNT(DISTINCT id_session) AS total_sessions
FROM (
    WITH filtered_traces AS (
        SELECT id_session, id_trace, id_user
        FROM datalake_langfuse_clean.traces
        WHERE contains(tags, 'wall_e')
    ),
    filtered_observations AS (
        SELECT id_trace
        FROM datalake_langfuse_clean.observations
        WHERE name IN ('ForRentOffboardingAgentV1')
    ),
    unified_scores AS (
        SELECT id_trace, id_session, name, string_value AS Category, value, comment, ts_created
        FROM datalake_langfuse_clean.scores
    ),
    tb_base AS (
        SELECT
            c.id_session,
            c.id_trace,
            c.id_user,
            b.ts_created,
            m.ts_created                                                        AS ts_created_message,
            COALESCE(s1.name,     s2.name)                                      AS name,
            COALESCE(s1.Category, s2.Category)                                  AS Category,
            COALESCE(s1.comment,  s2.comment)                                   AS comment,
            CAST(COALESCE(s1.ts_created, s2.ts_created) AS TIMESTAMP(3) WITH TIME ZONE) AS ts_created_score,
            b.channel,
            COALESCE(s1.value, s2.value)                                        AS value,
            b.is_escalated,
            b.first_queue,
            b.last_queue,
            m.role,
            LAG(b.ts_created) OVER (PARTITION BY c.id_user    ORDER BY b.ts_created) AS ts_last_session,
            LAG(m.role)        OVER (PARTITION BY c.id_session ORDER BY m.ts_created) AS prev_role,
            LAG(m.ts_created)  OVER (PARTITION BY c.id_session ORDER BY m.ts_created) AS prev_ts_created
        FROM filtered_traces c
        INNER JOIN filtered_observations o
            ON c.id_trace = o.id_trace
        LEFT JOIN datalake_chatbot.sessions b
            ON CAST(c.id_session AS VARCHAR) = CAST(b.id_langfuse_session AS VARCHAR)
        LEFT JOIN unified_scores s1
            ON c.id_trace = s1.id_trace
        LEFT JOIN unified_scores s2
            ON CAST(c.id_session AS VARCHAR) = CAST(s2.id_session AS VARCHAR)
        LEFT JOIN datalake_copilot_service_clean.message m
            ON CAST(b.id_session AS VARCHAR) = CAST(m.id_session AS VARCHAR)
    )
    SELECT
        id_session, id_trace, id_user,
        ts_created, ts_created_message,
        name, Category, comment, ts_created_score,
        channel, value,
        is_escalated, first_queue, last_queue,
        role, prev_role, prev_ts_created,
        MAX(
            CASE
                WHEN DATE_DIFF('hour', ts_last_session, ts_created) <= 48
                     AND ts_last_session <> ts_created
                     AND ts_last_session IS NOT NULL
                THEN 1 ELSE 0
            END
        ) OVER (PARTITION BY id_user) AS recontact_max
    FROM tb_base
) AS virtual_table
WHERE ts_created >= TIMESTAMP '2026-01-01 00:00:00.000000'
  AND ts_created <  TIMESTAMP '2027-01-01 00:00:00.000000'
GROUP BY
    date_trunc('day', CAST(ts_created AS TIMESTAMP)),
    is_escalated
ORDER BY total_sessions DESC
LIMIT 1000
```
