# Isaias Conversions

## Ownership

**Data Owner:**
- alexandre.gimenez@quintoandar.com.br

**Data Steward:**
- alexandre.gimenez@quintoandar.com.br

## Overview

**Isaias Conversions** measures the rate at which in-scope Isaias chatbot sessions ("demand") convert property owners down the supply funnel — to **opportunity** (D2O) and to **first listing** (D2L) — split by whether Isaias closed the conversion **autonomously** (`tp_origin_conversion = 'isaias'`) or a human inbound analyst closed it after handoff. **Total** = Autonomous + Human; **Autonomous** isolates fully bot-driven conversions. The document also defines **% Escalation to Inside Sales**, the share of sessions handed off to the IS human queue.

The naive path — dividing every attributed conversion by every session — is wrong: a lead touched by several sessions would be credited to each, and pooling autonomous with human conversions obscures how much of each conversion Isaias drove on its own. The correct number anchors on the preprocessed session-supply ledger built from `datalake_supply_flows.isaias_session_attribution` (unioned with `datalake_gsheets_clean.isaias_session_fallback`), enriched from both Sauron and **Support Sessions Service (SSS)**, with **valid attribution = the last session each lead appears in**, and reports on **coincident date** (`event_date`, the day the conversion occurred).

**Every Isaias session is end-to-end. Brazil (BR), RENT and SALE.**

## Related Domain Entities

- Supply

## Catalog

| Metric | Type |
| :---- | :---- |
| Isaias Demand-to-Listing Conversion Rate — Total | OKR |
| Isaias Demand-to-Listing Conversion Rate — Autonomous | Health Metric |
| Isaias Demand-to-Opportunity Conversion Rate — Total | Health Metric |
| Isaias Demand-to-Opportunity Conversion Rate — Autonomous | Health Metric |
| % Escalation to Inside Sales (Isaias) | Health Metric |

## DataHub Catalog

- **This metric's data product**: `urn:li:dataProduct:isaias-conversions`
- **Upstream domain entity data product**: `urn:li:dataProduct:supply`

## Glossary and Synonyms

- **Isaias Conversions**, **conversões do Isaías**, **conversão do bot do proprietário** → this metric family
- **D2O**, **Demand-to-Opportunity**, **sessão → oportunidade**, **conversão de demanda para oportunidade** → session-to-opportunity conversion rate
- **D2L**, **Demand-to-Listing**, **demand to first listing**, **sessão → primeira captação**, **conversão de demanda para listing** → session-to-first-listing conversion rate
- **Total** → Autonomous + Human conversions (`isaias_autonomous_conversion OR isaias_human_conversion`)
- **Autonomous**, **autônoma**, **conversão do Isaías** → Isaias closed the conversion end-to-end (`tp_origin_conversion = 'isaias'` / `isaias_autonomous_conversion = TRUE`)
- **Human**, **conversão humana**, **transbordo convertido** → inbound analyst closed within 24 h of session start (`isaias_human_conversion = TRUE`)
- **Demand**, **demanda**, **session**, **sessão**, **contact**, **contato** → an in-scope Isaias session (one row in the ledger `session_dim`); the terms are used interchangeably here
- **% Escalation to Inside Sales**, **taxa de transbordo para IS**, **perc_esc_is** → share of sessions escalated to the IS human queue (`LOWER(department) LIKE '%is%'`)

## Scope

**Included**: in-scope Isaias sessions across both hosts (`bot` = standalone Isaias or Isaias inside Wall-E / Mora) from the ledger `session_dim` base (`datalake_supply_flows.isaias_session_attribution` unioned with `datalake_gsheets_clean.isaias_session_fallback`), including SSS-only sessions resolved via `id_sss_session`, and their **validly attributed** `opportunity` / `first_listing` conversions from `dw_growth.obt_supply`, on **coincident date** (`event_date`) within the analysis window. Segmentable by `bot`, `source_environment`, `nm_business_context` (RENT / SALE), and time grain (`event_date`).

**Excluded**: sessions without `id_langfuse_session` or with neither a Sauron id nor an SSS `public_id`; any window before **August 2026**; conversions credited to a session that is not the lead's last touching session (invalid attribution); conversions whose `event_date` falls outside the window; any signal that would require Langfuse behaviour flags (Langfuse is ad-hoc only, not a metric source).

## Calculation

Each conversion metric is a ratio of **deduplicated converted supplies** to **distinct sessions**. The denominator is the session count; each numerator counts distinct converted supplies at the target funnel step. Autonomy is a per-supply property already resolved by the ledger (`isaias_autonomous_conversion`, `isaias_human_conversion`).

```
sessions            = COUNT(DISTINCT id_langfuse_session)  over session_start events

D2O_total = COUNT(DISTINCT supply_key WHERE funnel_step = 'opportunity'    AND (autonomous OR human)) / sessions
D2O_auto  = COUNT(DISTINCT supply_key WHERE funnel_step = 'opportunity'    AND  autonomous)           / sessions
D2L_total = COUNT(DISTINCT supply_key WHERE funnel_step = 'first_listing'  AND (autonomous OR human)) / sessions
D2L_auto  = COUNT(DISTINCT supply_key WHERE funnel_step = 'first_listing'  AND  autonomous)           / sessions

% Escalation to IS = COUNT(DISTINCT id_langfuse_session WHERE LOWER(department) LIKE '%is%') / sessions
```

where `supply_key = CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)` — the deduplication key **never** includes `cd_funnel_step` (a supply can appear at both `opportunity` and `first_listing`), and `autonomous` / `human` are the ledger's `isaias_autonomous_conversion` / `isaias_human_conversion` flags (Autonomous takes priority; a supply is Human only if not Autonomous). The full ledger construction — session isolation, both attribution keys, last-session validity, the OPPORTUNITY 24 h window for Human — is documented in the **Supply** domain entity (`../domain_entities/supply.md`, Golden Query 2) and reproduced (trimmed to this metric's columns) in the golden query below.

### Canonical Filter

The metric universe is defined by the ledger (both hosts, all in-scope sessions) plus a **coincident-date** window on the ledger output:

```sql
-- On the ledger output (both event types carry event_date):
event_date >= DATE '{start_date}'   -- window start
AND event_date < DATE {end_date} -- window end (half-open)
```

Inside the ledger, scope the session base and its lead lookback:

```sql
-- session base (August 2026 floor on both bounds)
d.ts_session_start >= from_iso8601_timestamp('{start_date}T00:00:00Z')   -- {start_date} >= 2026-08-01
-- obt lead lookback ({obt_start_date} = a few days before {start_date}, never earlier than 2026-08-01)
o."date" >= DATE {obt_start_date}
```

**Data availability**: the ledger is scoped to **August 2026 onward** (`isaias_session_attribution` has no earlier backfill). Both `{start_date}` and `{obt_start_date}` must be `>= DATE '2026-08-01'`.

**Warning**: report on `event_date` (coincident — the day the conversion occurred), **not** `session_date`. `session_date` (= `DATE(ts_session_start)`) is the **cohort** axis and is only used when a cohort view is explicitly requested. Mixing the two produces numerators and denominators on different time bases.

### Nuances

There are no external weights or parameters — every input comes from the ledger.

| Column | Description |
| :---- | :---- |
| `event_type` | `'session_start'` (denominator, one per session) or `'conversao'` (numerator, one per session × valid converted supply). |
| `id_langfuse_session` | Session identity used for **all session counts** (denominator and escalation), counted with `COUNT(DISTINCT ...)`. |
| `id_session` | Unified attribution grain (`COALESCE(id_sauron_session, id_sss_session)`); used internally for last-session attribution and conversion joins — **not** for session-volume counts. |
| `funnel_step` | Target stage of the conversion: `'opportunity'` (D2O) or `'first_listing'` (D2L). |
| `isaias_autonomous_conversion` / `isaias_human_conversion` | Supply-level conversion flags from the ledger. |
| `department` | `COALESCE(sauron.department, sss.department)` — Sauron first, SSS fallback; `LOWER(department) LIKE '%is%'` marks escalation to Inside Sales. |
| `bot` / `source_environment` | Segmentation dimensions (host and entry channel; `source_environment` = `COALESCE(sauron.source_environment, sss.source_env)`). |

**Operator-precedence trap (critical)**: the Total numerators combine three predicates with `OR`. SQL binds `AND` tighter than `OR`, so `... AND funnel_step = 'first_listing' AND isaias_autonomous_conversion OR isaias_human_conversion` parses as `(... AND funnel_step = 'first_listing' AND isaias_autonomous_conversion) OR (isaias_human_conversion)` — which counts **every** human conversion regardless of `funnel_step`, inflating D2L Total with opportunity-step human conversions. **Always parenthesize**: `AND (isaias_autonomous_conversion OR isaias_human_conversion)`.

**Session identity**: sessions are counted by `COUNT(DISTINCT id_langfuse_session)`, not `id_sauron_session` or `id_session`. Every in-scope Isaias session has a Langfuse id — the ledger enforces this in `session_base` (rows without `id_langfuse_session` are dropped). The unified `id_session` (`COALESCE(id_sauron_session, id_sss_session)`) is the **attribution grain** for linking leads and conversions across the Sauron → SSS migration — use it in the ledger internals only, never for session-volume counts.

**Division guard**: wrap each rate with `NULLIF(sessions, 0)` (or `TRY(...)`) so an empty segment yields NULL rather than an error; report NULL as "no data", not 0%.

**Attribution & autonomy definitions live in Supply**: do not re-derive them here — see `../domain_entities/supply.md` (Critical Rules and Golden Query 2).

**Segmentation and time grain**: the ledger output carries `bot` (Isaias vs Wall-E / Mora), `source_environment`, `nm_business_context` (RENT / SALE), `lead_acquisition_type`, and both date axes. Add any of these to the outer `GROUP BY` to segment. For a time series, add `DATE_TRUNC('month' | 'week' | 'day', event_date)` to the `SELECT` and `GROUP BY` and widen the `event_date` window. Because `event_date` = session-start day for `session_start` rows and conversion day for `conversao` rows, bucketing by it gives the **coincident** rate at that grain (sessions counted in the period they started, conversions in the period they occurred). Use `DATE_TRUNC(..., session_date)` instead only for an explicitly requested cohort view.

## Dos and Don'ts

**Do:**

- Parenthesize `(isaias_autonomous_conversion OR isaias_human_conversion)` in every Total numerator.
- Count sessions with `COUNT(DISTINCT id_langfuse_session)` over `session_start` events, for both the denominator and the escalation numerator.
- Deduplicate converted supplies on `CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)` — never include `cd_funnel_step`.
- Report on `event_date` (coincident) by default; only switch to `session_date` for an explicitly requested cohort view.
- Segment by `bot` and `source_environment` when host / channel breakdowns are needed.

**Don't:**

- Don't rely on `AND autonomous OR human` without parentheses — it silently inflates Total rates.
- Don't include `cd_funnel_step` in the dedup key — a single supply reaches both `opportunity` and `first_listing`.
- Don't credit a lead's conversion to more than one session — the ledger's last-session attribution already enforces this; don't re-open it.
- Don't use Langfuse observations / flags to compute these metrics — Langfuse is ad-hoc only.

## Golden Queries

Produces the Isaias conversion rates and volumes by `bot` and `source_environment`. The subquery is a **trimmed mirror** of the session-supply ledger in **Supply** (`../domain_entities/supply.md`, Golden Query 2) through the `events` CTE — same session dedup, SSS enrichment, and attribution logic; omits `has_draft_assigned` and extra OBT dimension columns from the full ledger `SELECT`. **Keep both in sync** when editing the ledger. What is exclusive to this metric is the outer aggregation layer (the D2O / D2L / autonomous / total ratios and the escalation share), with the `OR` predicates correctly parenthesized.

```sql
SELECT
    bot,
    source_environment,

    -- Session denominator: distinct Langfuse sessions that started
    COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END) AS sessions,

    -- Volumes (dedup key = sk_supply + business context; NEVER include funnel_step)
    COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND funnel_step = 'opportunity'
         AND (isaias_autonomous_conversion OR isaias_human_conversion)
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)
    END) AS opportunities,
    COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND funnel_step = 'first_listing'
         AND (isaias_autonomous_conversion OR isaias_human_conversion)
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context)
    END) AS first_listings,
    COUNT(DISTINCT CASE WHEN event_type = 'session_start' AND LOWER(department) LIKE '%is%' THEN id_langfuse_session END) AS escalated_is,

    -- D2O (session -> opportunity)
    ROUND(COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND funnel_step = 'opportunity'
         AND (isaias_autonomous_conversion OR isaias_human_conversion)
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context) END) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END), 0), 4) AS d2o_total_rate,
    ROUND(COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND funnel_step = 'opportunity'
         AND isaias_autonomous_conversion
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context) END) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END), 0), 4) AS d2o_auto_rate,

    -- D2L (session -> first listing)
    ROUND(COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND funnel_step = 'first_listing'
         AND (isaias_autonomous_conversion OR isaias_human_conversion)
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context) END) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END), 0), 4) AS d2l_total_rate,
    ROUND(COUNT(DISTINCT CASE
        WHEN event_type = 'conversao' AND funnel_step = 'first_listing'
         AND isaias_autonomous_conversion
        THEN CONCAT(CAST(sk_supply AS VARCHAR), '_', nm_business_context) END) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END), 0), 4) AS d2l_auto_rate,

    -- % Escalation to Inside Sales
    ROUND(COUNT(DISTINCT CASE WHEN event_type = 'session_start' AND LOWER(department) LIKE '%is%' THEN id_langfuse_session END) * 1.0
        / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'session_start' THEN id_langfuse_session END), 0), 4) AS esc_is_rate
FROM (
    -- ===== Session-supply ledger — trimmed mirror of supply.md Query 2 through events =====
    WITH
    session_base_raw AS (
        SELECT
            id_langfuse_session, id_sss_session, id_sauron_session,
            resolved_lead_id, bot, false AS has_reschedule_event,
            lead_acquisition_type, CAST(ts_created AS TIMESTAMP) AS ts_session_start,
            2 AS source_priority
        FROM datalake_gsheets_clean.isaias_session_fallback
        WHERE ts_created <> ''
        UNION ALL
        SELECT
            id_langfuse_session, id_sss_session, id_sauron_session,
            resolved_lead_id, bot, has_reschedule_event,
            lead_acquisition_type, ts_session_start,
            1 AS source_priority
        FROM datalake_supply_flows.isaias_session_attribution
    ),
    session_base AS (
        SELECT
            id_langfuse_session, id_sss_session, id_sauron_session,
            resolved_lead_id, bot, has_reschedule_event,
            lead_acquisition_type, ts_session_start
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY id_langfuse_session
                    ORDER BY source_priority, ts_session_start DESC
                ) AS rn
            FROM session_base_raw
            WHERE NULLIF(id_langfuse_session, '') IS NOT NULL
        )
        WHERE rn = 1
    ),
    session_dim AS (
        SELECT
            d.id_sauron_session, d.id_langfuse_session, d.id_sss_session,
            COALESCE(NULLIF(d.id_sauron_session, ''), NULLIF(d.id_sss_session, '')) AS id_session,
            d.resolved_lead_id,
            COALESCE(d.lead_acquisition_type, 'no_lead') AS lead_acquisition_type,
            d.bot, d.has_reschedule_event,
            COALESCE(ss.source_environment, sss.source_env) AS source_environment,
            COALESCE(ss.department, sss.department) AS department,
            d.ts_session_start
        FROM session_base d
        LEFT JOIN datalake_sauron_clean.session ss
            ON CAST(ss.id AS VARCHAR) = d.id_sauron_session
        LEFT JOIN datalake_support_session_service_clean.support_session sss
            ON sss.public_id = d.id_sss_session
            AND sss.public_id IS NOT NULL
        WHERE COALESCE(NULLIF(d.id_sauron_session, ''), NULLIF(d.id_sss_session, '')) IS NOT NULL
            AND d.ts_session_start >= from_iso8601_timestamp('{start_date}T00:00:00Z')
    ),
    session_keys AS (
        SELECT id_sauron_session AS session_key, id_session, ts_session_start
        FROM session_dim
        WHERE NULLIF(id_sauron_session, '') IS NOT NULL
        UNION
        SELECT id_sss_session AS session_key, id_session, ts_session_start
        FROM session_dim
        WHERE NULLIF(id_sss_session, '') IS NOT NULL
    ),
    lead_session_candidates AS (
        SELECT resolved_lead_id AS lead_id, id_session, ts_session_start
        FROM session_dim
        WHERE resolved_lead_id IS NOT NULL
        UNION
        SELECT CAST(o.sk_lead AS VARCHAR), sk.id_session, sk.ts_session_start
        FROM dw_growth.obt_supply o
        JOIN session_keys sk ON o.sk_chat_session = sk.session_key
        WHERE o.sk_chat_session IS NOT NULL
            AND o.sk_chat_session <> '-1'
            AND o.sk_lead IS NOT NULL
            AND o."date" >= DATE {obt_start_date}   -- >= 2026-08-01; a few days before {start_date}
    ),
    valid_attribution AS (
        SELECT lead_id, id_session
        FROM (
            SELECT lead_id, id_session,
                   ROW_NUMBER() OVER (PARTITION BY lead_id ORDER BY ts_session_start DESC) AS rn
            FROM lead_session_candidates
        )
        WHERE rn = 1
    ),
    conversion_time AS (
        SELECT id_lead_ebdb, business_context, MIN(ts_event_adjusted) AS ts_event_adjusted
        FROM datalake_supply_flows.supply_events_tracking
        WHERE funnel_step = 'OPPORTUNITY' AND id_lead_ebdb IS NOT NULL
        GROUP BY 1, 2
    ),
    conv_rows AS (
        SELECT
            sd.id_session, sd.id_sauron_session, sd.id_langfuse_session, sd.id_sss_session,
            sd.lead_acquisition_type, sd.bot, sd.has_reschedule_event, sd.source_environment, sd.department, sd.ts_session_start,
            CAST(o.sk_lead AS VARCHAR) AS lead_id,
            o.sk_supply, o.nm_business_context, o.cd_funnel_step, o."date" AS event_date,
            (o.tp_origin_conversion = 'isaias') AS is_autonomous,
            (
                o.tp_origin_conversion <> 'isaias'
                AND o.planning_operation = 'Inbound'
                AND ct.ts_event_adjusted >= sd.ts_session_start
                AND ct.ts_event_adjusted <  sd.ts_session_start + INTERVAL '24' HOUR
            ) AS is_human
        FROM dw_growth.obt_supply o
        JOIN valid_attribution va ON CAST(o.sk_lead AS VARCHAR) = va.lead_id
        JOIN session_dim sd ON va.id_session = sd.id_session
        LEFT JOIN conversion_time ct
            ON o.sk_lead = ct.id_lead_ebdb AND o.nm_business_context = ct.business_context
        WHERE o.cd_funnel_step IN ('opportunity', 'first_listing')
            AND o."date" >= DATE {obt_start_date}
    ),
    valid_supply AS (
        SELECT id_session, sk_supply, nm_business_context,
               BOOL_OR(is_autonomous) AS supply_autonomous,
               (BOOL_OR(is_human) AND NOT BOOL_OR(is_autonomous)) AS supply_human
        FROM conv_rows
        GROUP BY id_session, sk_supply, nm_business_context
    ),
    events AS (
        SELECT
            'session_start' AS event_type,
            CAST(ts_session_start AS DATE) AS event_date,
            id_session, id_sauron_session, id_langfuse_session, id_sss_session,
            CAST(ts_session_start AS DATE) AS session_date,
            source_environment, department, bot, has_reschedule_event, lead_acquisition_type,
            resolved_lead_id AS lead_id,
            CAST(NULL AS VARCHAR) AS nm_business_context,
            CAST(NULL AS VARCHAR) AS funnel_step,
            CAST(NULL AS VARCHAR) AS sk_supply,
            CAST(NULL AS BOOLEAN) AS isaias_autonomous_conversion,
            CAST(NULL AS BOOLEAN) AS isaias_human_conversion
        FROM session_dim
        UNION ALL
        SELECT
            'conversao' AS event_type,
            cr.event_date,
            cr.id_session, cr.id_sauron_session, cr.id_langfuse_session, cr.id_sss_session,
            CAST(cr.ts_session_start AS DATE) AS session_date,
            cr.source_environment, cr.department, cr.bot, cr.has_reschedule_event, cr.lead_acquisition_type,
            cr.lead_id,
            cr.nm_business_context,
            cr.cd_funnel_step AS funnel_step,
            cr.sk_supply,
            vs.supply_autonomous AS isaias_autonomous_conversion,
            vs.supply_human AS isaias_human_conversion
        FROM conv_rows cr
        JOIN valid_supply vs
            ON cr.id_session = vs.id_session
            AND cr.sk_supply = vs.sk_supply
            AND cr.nm_business_context = vs.nm_business_context
        WHERE vs.supply_autonomous OR vs.supply_human
    )
    SELECT * FROM events
) AS ledger
WHERE event_date >= DATE '{start_date}'
    AND event_date < DATE {end_date}
GROUP BY bot, source_environment
ORDER BY d2l_total_rate DESC
```
