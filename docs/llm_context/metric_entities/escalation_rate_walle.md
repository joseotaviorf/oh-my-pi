# % Escalation Rate (Wall-E)

## Ownership

**Data Owner:**
- jorge.ribeiro@quintoandar.com.br

**Data Steward:**
- jorge.ribeiro@quintoandar.com.br

## Overview

**% Escalation Rate (Wall-E)** is the share of Wall-E chatbot sessions that were escalated to
human support. It is a direct ratio on `datalake_chatbot.sessions` — there is no weighting or
pooling step — but it must always be scoped to `bot = 'wall-e'` in both numerator and
denominator, otherwise it silently reports the escalation rate across all bots.

**Exists exclusively for the Wall-E bot. Do not use this definition for other bots (e.g.
Isaias, old bot) — those need their own escalation rate computed with the same pattern but a
different bot filter.**

## Related Business Entities

- Chatbot Sessions

## Catalog

| Metric | Type |
| :---- | :---- |
| % Escalation Rate (Wall-E) | OKR |

## MBR

**Name** Post Contract
**Category** Resolution Effectiveness

## DataHub Catalog

- **This metric's data product**: `urn:li:dataProduct:escalation-rate-wall-e`
- **Upstream business entity data product**: `urn:li:dataProduct:chatbot-sessions`

## Glossary and Synonyms

- **Escalation Rate**, **Wall-E Escalation Rate**, **% Escalation Rate**, **taxa de
  escalonamento do Wall-E** → this metric

## Scope

**Included**: All Wall-E sessions (`bot = 'wall-e'`) created in the period, on any channel
(WhatsApp or in-app).

**Excluded**: Sessions from any other bot (e.g. `isaias`, `old bot`). Sessions outside the
selected `ts_created` period.

## Calculation

The naive path — computing escalation rate over all `datalake_chatbot.sessions` rows without
filtering `bot` — is wrong because it blends Wall-E's escalation behavior with every other
bot's, producing a number that does not correspond to any single bot.

The correct calculation is:

```
% Escalation Rate (Wall-E) = COUNT_IF(is_escalated = TRUE AND bot = 'wall-e')
                              / COUNT_IF(bot = 'wall-e')
```

where the numerator counts Wall-E sessions flagged as escalated (`sessions.is_escalated`), and
the denominator counts all Wall-E sessions in the same period.

### Canonical Filter

Apply on `datalake_chatbot.sessions`:

```sql
bot = 'wall-e'
-- Change both bounds to the analysis window you want (half-open interval).
AND ts_created >= TIMESTAMP '2026-07-01 00:00:00'
AND ts_created < TIMESTAMP '2026-08-01 00:00:00'
```

**Warning**: Filtering only on `is_escalated` for the numerator without also restricting the
denominator to `bot = 'wall-e'` inflates or deflates the rate — the denominator must be Wall-E
sessions only, not all sessions.

### Nuances

There are no weights or external parameters for this metric — it is a direct `COUNT_IF` ratio
on `sessions`.

| Column | Description |
| :---- | :---- |
| `is_escalated` | BOOLEAN. TRUE when the bot handed the session off to a human analyst. |
| `bot` | VARCHAR. Must equal `'wall-e'` for this metric. |
| `ts_created` | TIMESTAMP(3) WITH TIME ZONE. Session creation timestamp — use for period filtering (`DATE(ts_created)` for daily grain). |

**Join key**: N/A — single-table metric.

**Fallback**: N/A — no external parameter source; a period with zero Wall-E sessions simply
yields NULL (0/0), report as "no data" rather than 0%.

## Dos and Don'ts

**Do:**

- Apply `bot = 'wall-e'` to both numerator and denominator.
- Filter the period on `ts_created`, not `ts_updated`.

**Don't:**

- Don't compute the escalation rate across all bots and then assume it represents Wall-E.
- Don't use `COUNT(*)` without the `bot = 'wall-e'` filter as the denominator.

## Golden Queries

Computes the daily % Escalation Rate for Wall-E. The component pattern (per-day, per-bot
escalation count over total count) reproduces the general "Session volume by bot and channel"
golden query documented in the Chatbot Sessions business entity; what is exclusive to this
metric is the `bot = 'wall-e'` restriction applied to the whole universe (not just the
numerator).

```sql
WITH component AS (
    -- Component metric — same pattern as chatbot_sessions.md "Session volume by bot" golden query.
    SELECT
        DATE(s.ts_created) AS dt_session,
        COUNT(*) AS total_sessions,
        COUNT_IF(s.is_escalated) AS escalated_sessions
    FROM datalake_chatbot.sessions AS s
    WHERE s.bot = 'wall-e'
        -- Change both bounds to the analysis window you want (half-open interval).
        AND s.ts_created >= TIMESTAMP '2026-07-01 00:00:00'
        AND s.ts_created < TIMESTAMP '2026-08-01 00:00:00'
    GROUP BY 1
)
SELECT
    dt_session,
    ROUND(CAST(escalated_sessions AS DOUBLE) / total_sessions, 4) AS escalation_rate_wall_e
FROM component
ORDER BY 1
```

