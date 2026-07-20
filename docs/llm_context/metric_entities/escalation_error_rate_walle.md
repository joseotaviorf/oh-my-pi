# % Escalation Error Rate (Wall-E)

## Ownership

**Data Owner:**
- jorge.ribeiro@quintoandar.com.br

**Data Steward:**
- jorge.ribeiro@quintoandar.com.br

## Overview

**% Escalation Error Rate (Wall-E)** is the share of escalated Wall-E sessions that landed in a
different support queue than the one they were first routed to (`first_queue != last_queue`),
restricted to a fixed, curated list of front-facing queues. The naive calculation — comparing
`first_queue` and `last_queue` over all escalated sessions and all queue values — overstates the
error rate, because it includes internal/back-office queues and non-front queues that are not
part of the official metric's universe.

**Exists exclusively for the Wall-E bot, and only for escalations that both started and ended in
one of the eleven curated front-facing queues listed in Scope below.**

## Related Business Entities

- Chatbot Sessions

## MBR

- Post Contract

## DataHub Catalog

- **This metric's data product**: `urn:li:dataProduct:escalation-error-rate-wall-e`
- **Upstream business entity data product**: `urn:li:dataProduct:chatbot-sessions`

## Glossary and Synonyms

- **Escalation Error Rate**, **Wall-E Escalation Error Rate**, **% Escalation Error Rate**,
  **taxa de erro de escalonamento do Wall-E** → this metric

## Scope

**Included**: Wall-E sessions (`bot = 'wall-e'`) that were escalated (`is_escalated = TRUE`) in
the period, where both `first_queue` and `last_queue` are one of:

- `CX Pagamentos [FRONT] [POS]`
- `CX Parceiros [FRONT] [PRE]`
- `CX Visitas [FRONT] [PRE]`
- `CX Propostas [FRONT] [PRE]`
- `CX Mudança [FRONT] [POS]`
- `CX Rescisão [FRONT] [POS]`
- `CX Reparos [FRONT] [POS]`
- `[WH] Credito [FRONT]`
- `[WH] Closing [FRONT]`
- `[IS] Inbound Principal [FRONT][PRE]`
- `CX Ongoing [FRONT] [POS]`

**Excluded**: Non-escalated sessions; sessions from other bots; escalated sessions where
`first_queue` or `last_queue` falls outside the curated list above (e.g. internal/back-office
queues) — including them in either numerator or denominator inflates or dilutes the official
rate.

## Calculation

The naive path — `COUNT_IF(first_queue != last_queue) / COUNT_IF(is_escalated)` over the full
`sessions` table — is wrong for two reasons: (1) it does not restrict to `bot = 'wall-e'`, mixing
in other bots' routing behavior, and (2) it does not restrict `first_queue`/`last_queue` to the
curated front-facing queue list, so a mismatch involving a back-office or non-front queue counts
as an "error" even though it is out of scope for this metric.

The correct calculation is:

```
% Escalation Error Rate (Wall-E) = COUNT_IF(first_queue != last_queue)
                                    / COUNT_IF(is_escalated = TRUE)
```

computed only over the subset of `datalake_chatbot.sessions` where `bot = 'wall-e'`,
`is_escalated = TRUE`, and both `first_queue` and `last_queue` are in the curated queue list —
i.e. the numerator and denominator share the same filtered universe; the numerator additionally
requires `first_queue != last_queue`.

### Canonical Filter

Apply on `datalake_chatbot.sessions`:

```sql
bot = 'wall-e'
AND is_escalated = TRUE
AND first_queue IN (
    'CX Pagamentos [FRONT] [POS]',
    'CX Parceiros [FRONT] [PRE]',
    'CX Visitas [FRONT] [PRE]',
    'CX Propostas [FRONT] [PRE]',
    'CX Mudança [FRONT] [POS]',
    'CX Rescisão [FRONT] [POS]',
    'CX Reparos [FRONT] [POS]',
    '[WH] Credito [FRONT]',
    '[WH] Closing [FRONT]',
    '[IS] Inbound Principal [FRONT][PRE]',
    'CX Ongoing [FRONT] [POS]'
)
AND last_queue IN (
    'CX Pagamentos [FRONT] [POS]',
    'CX Parceiros [FRONT] [PRE]',
    'CX Visitas [FRONT] [PRE]',
    'CX Propostas [FRONT] [PRE]',
    'CX Mudança [FRONT] [POS]',
    'CX Rescisão [FRONT] [POS]',
    'CX Reparos [FRONT] [POS]',
    '[WH] Credito [FRONT]',
    '[WH] Closing [FRONT]',
    '[IS] Inbound Principal [FRONT][PRE]',
    'CX Ongoing [FRONT] [POS]'
)
AND ts_created >= TIMESTAMP '{start_date}'
AND ts_created < TIMESTAMP '{end_date}'
```

**Warning**: Filtering only on `bot = 'wall-e'` and `is_escalated` (the pattern used by the
generic golden query in the Chatbot Sessions business entity) — without also restricting
`first_queue`/`last_queue` to the eleven curated queues — includes back-office and non-front
queue transitions that do not compose the official metric. Both `first_queue` AND `last_queue`
must be in the list; a session with only one side in-list is out of scope.

### Nuances

There is no external weight/parameter source for this metric — the "parameter" is the fixed
queue whitelist itself, which is a business-defined list, not a queryable table. Treat the list
as a versioned constant: if the business updates which queues are in scope, this document's
Scope and Canonical Filter sections must be updated together.

| Column | Description |
| :---- | :---- |
| `first_queue` | VARCHAR. Queue the session was first routed to on escalation. Must be in the curated list. |
| `last_queue` | VARCHAR. Queue the session ended in. Must be in the curated list. A mismatch vs. `first_queue` defines an escalation error. |
| `is_escalated` | BOOLEAN. Must be TRUE — this metric is only defined over escalated sessions. |
| `bot` | VARCHAR. Must equal `'wall-e'`. |
| `ts_created` | TIMESTAMP(3) WITH TIME ZONE. Session creation timestamp — use for period filtering. |

**Join key**: N/A — single-table metric; the queue whitelist is applied as an `IN` filter, not a
join.

**Fallback**: N/A. If a period has zero qualifying escalated sessions after the queue filter,
report as "no data" rather than 0%.

## Dos and Don'ts

**Do:**

- Apply `bot = 'wall-e'`, `is_escalated = TRUE`, and the curated `first_queue`/`last_queue`
  `IN (...)` filter to the shared numerator/denominator universe.
- Filter the period on `ts_created`.

**Don't:**

- Don't reuse the Chatbot Sessions business entity's generic "Escalation error rate" golden
  query as-is — it lacks the `bot = 'wall-e'` and queue-whitelist restrictions that make this the
  official metric.
- Don't count a `first_queue != last_queue` mismatch as an error if either queue value falls
  outside the eleven curated queues.

## Golden Queries

Computes % Escalation Error Rate for Wall-E, restricted to the curated front-facing queue list.
The component pattern (per bot/queue-pair escalation counts) reproduces the "Escalation error
rate" golden query already documented in the Chatbot Sessions business entity; what is exclusive
to this metric is the `bot = 'wall-e'` filter plus the `first_queue`/`last_queue` queue whitelist
applied to the shared universe.

```sql
WITH allowed_queues AS (
    SELECT * FROM (VALUES
        ('CX Pagamentos [FRONT] [POS]'),
        ('CX Parceiros [FRONT] [PRE]'),
        ('CX Visitas [FRONT] [PRE]'),
        ('CX Propostas [FRONT] [PRE]'),
        ('CX Mudança [FRONT] [POS]'),
        ('CX Rescisão [FRONT] [POS]'),
        ('CX Reparos [FRONT] [POS]'),
        ('[WH] Credito [FRONT]'),
        ('[WH] Closing [FRONT]'),
        ('[IS] Inbound Principal [FRONT][PRE]'),
        ('CX Ongoing [FRONT] [POS]')
    ) AS t(queue_name)
),
component AS (
    -- Component metric — same pattern as chatbot_sessions_context.md "Escalation error rate" golden query.
    SELECT
        COUNT_IF(s.first_queue != s.last_queue) AS escalation_errors,
        COUNT(*) AS escalated_sessions
    FROM datalake_chatbot.sessions AS s
    WHERE s.bot = 'wall-e'
        AND s.is_escalated = TRUE
        AND s.first_queue IN (SELECT queue_name FROM allowed_queues)
        AND s.last_queue IN (SELECT queue_name FROM allowed_queues)
        AND s.ts_created >= TIMESTAMP '{start_date}'
        AND s.ts_created < TIMESTAMP '{end_date}'
)
SELECT
    ROUND(CAST(escalation_errors AS DOUBLE) / escalated_sessions, 4) AS escalation_error_rate_wall_e
FROM component
```

## Superset Golden Assets

- **Wall-E Escalation Error Rate chart** — reference Superset chart used as the canonical
  starting point for this metric. URN: `urn:li:chart:(superset,chart.51683)`
  ([link](https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.51683)/Documentation?is_lineage_mode=false)).
