## Overview

**NPS FR** is the official Net Promoter Score for the For Rent product. It is a **weighted average** of the NPS computed independently for each journey (onboarding, ongoing, offboarding), using quarterly weights defined by the CX team.

**This product exists exclusively for For Rent — there is no equivalent weighted NPS for FS or other products.**

## Related Business Entities

*   NPS
    

## DataHub Catalog

*   **Upstream business entity data product**: `urn:li:dataProduct:nps`
    

## Scope

**Included**: onboarding, ongoing, offboarding — IQ + PP, Brazil

**Excluded**: lost, po, ppm, international campaigns (mexico, bo), agents, brokers, test campaigns (`purpose = 'test'`)

## Calculation

Summing all onboarding, ongoing, and offboarding answers directly (simple pool) produces a **systematically incorrect** result — the response volumes per journey are very different from one another, distorting the resulting NPS by up to 5 points.

The correct calculation is:

```markup
NPS_FR = NPS_onboarding  * weight_onboarding
       + NPS_ongoing     * weight_ongoing
       + NPS_offboarding * weight_offboarding

```

where each `NPS_journey = (promoters − detractors) / total_journey × 100`.

### Canonical Filter

Apply on `dim_nps_campaign` when joining with `fact_nps_dispatches`:

```sql
business_context   = 'forRent'
AND customer_journey = 'true'   -- string literal, not a boolean
AND purpose          = 'main'

```

**Warning**: filtering only on `business_context = 'forRent'` without the other two fields includes lost, ppm, po, and other campaigns that are **not part of the official NPS FR**.

### Nuances

The weights are defined quarterly by the CX team in a GSheets spreadsheet. **Never hardcode the weights** — always read them from the table.

| Column | Description |
| --- | --- |
| `campaign_group` | Journey name: `onboarding`, `ongoing`, `offboarding` |
| `customer_journey` | Filter `= 'TRUE'` for NPS FR weights |
| `share` | Period weight, stored as a string `'25%'` — parse: `CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0` |
| `dt_start`, `dt_end` | Quarterly validity of the weight (quarter start and end dates) |
| `target` | Period NPS target (informational, do not use in the calculation) |

**Join key**: `campaign_group` ↔ journey derived from `metric_group` in `dim_nps_campaign`:

*   `metric_group LIKE '%onboarding%'` → `campaign_group = 'onboarding'`
    
*   `metric_group LIKE '%ongoing%'` → `campaign_group = 'ongoing'`
    
*   `metric_group LIKE '%offboarding%'`→ `campaign_group = 'offboarding'`
    

**Date join**: `CAST(month AS DATE) BETWEEN dt_start AND dt_end`

**Fallback**: if a month does not yet have a registered quarter in the weights table, use the most recent weight per journey via `ROW_NUMBER() OVER (PARTITION BY journey ORDER BY dt_end DESC)`.

&nbsp;

## Golden Query

```sql WITH journey_nps AS ( -- Component NPS per journey — same pattern as ../business_entities/nps.md (Query 1). -- Only addition here: derive the journey via metric_group to match the weights. SELECT date_trunc('month', CAST(dna.ts_answered AS TIMESTAMP)) AS month, CASE WHEN dnc.metric_group LIKE '%onboarding%' THEN 'onboarding' WHEN dnc.metric_group LIKE '%ongoing%' THEN 'ongoing' WHEN dnc.metric_group LIKE '%offboarding%' THEN 'offboarding' END AS journey, COUNT(*) AS total_responses, SUM(CASE WHEN dna.score_category = 'promoter' THEN 1 ELSE 0 END) AS promoters, SUM(CASE WHEN dna.score_category = 'detractor' THEN 1 ELSE 0 END) AS detractors, ROUND( (CAST(SUM(CASE WHEN dna.score_category = 'promoter' THEN 1 ELSE 0 END) AS DOUBLE) - CAST(SUM(CASE WHEN dna.score_category = 'detractor' THEN 1 ELSE 0 END) AS DOUBLE)) / COUNT(*) * 100, 1 ) AS nps_journey FROM dw_customer_satisfaction.fact_nps_dispatches AS fnd INNER JOIN dw_customer_satisfaction.dim_nps_answer AS dna ON fnd.sk_nps_answer = dna.sk_nps_answer INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc ON fnd.sk_nps_campaign = dnc.sk_nps_campaign WHERE fnd.is_answered = true AND dnc.business_context = 'forRent' AND dnc.customer_journey = 'true' AND dnc.purpose = 'main' AND CAST(dna.ts_answered AS TIMESTAMP) >= CAST(date_add('month', -24, current_date) AS TIMESTAMP) AND CAST(dna.ts_answered AS TIMESTAMP) < CAST(current_date AS TIMESTAMP) GROUP BY 1, 2 ), weights_raw AS ( -- Quarterly weights per journey — read from GSheets, never hardcoded SELECT campaign_group AS journey, CAST(dt_start AS DATE) AS dt_start, CAST(dt_end AS DATE) AS dt_end, CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0 AS weight FROM datalake_gsheets_clean.nps_target_share WHERE customer_journey = 'TRUE' AND share IS NOT NULL AND share != '' ), latest_weights AS ( -- Fallback: most recent weight per journey (months without a registered quarter) SELECT journey, weight FROM ( SELECT journey, weight, ROW_NUMBER() OVER (PARTITION BY journey ORDER BY dt_end DESC) AS rn FROM weights_raw ) AS sub WHERE rn = 1 ), journey_with_weight AS ( -- Deduplicates weights in case nps_target_share has overlapping intervals (manual GSheet). -- ROW_NUMBER ensures only one weight is applied per (month, journey). SELECT jn.*, w.weight, ROW_NUMBER() OVER (PARTITION BY jn.month, jn.journey ORDER BY w.dt_start DESC, w.dt_end DESC) AS rn FROM journey_nps AS jn LEFT JOIN weights_raw AS w ON jn.journey = w.journey AND CAST(jn.month AS DATE) BETWEEN w.dt_start AND w.dt_end ) SELECT d.month, ROUND(SUM(d.nps_journey * COALESCE(d.weight, lw.weight)), 1) AS nps_fr, SUM(d.total_responses) AS total_responses, MAX(CASE WHEN d.journey = 'onboarding' THEN d.nps_journey END) AS nps_onboarding, MAX(CASE WHEN d.journey = 'ongoing' THEN d.nps_journey END) AS nps_ongoing, MAX(CASE WHEN d.journey = 'offboarding' THEN d.nps_journey END) AS nps_offboarding, MAX(CASE WHEN d.journey = 'onboarding' THEN COALESCE(d.weight, lw.weight) END) AS weight_onboarding, MAX(CASE WHEN d.journey = 'ongoing' THEN COALESCE(d.weight, lw.weight) END) AS weight_ongoing, MAX(CASE WHEN d.journey = 'offboarding' THEN COALESCE(d.weight, lw.weight) END) AS weight_offboarding, MIN(CASE WHEN d.weight IS NULL THEN 'fallback' ELSE 'official' END) AS weight_source FROM (SELECT * FROM journey_with_weight WHERE rn = 1) AS d LEFT JOIN latest_weights AS lw ON d.journey = lw.journey GROUP BY d.month ORDER BY d.month` ``

## Dos and Don'ts

**Do:**

*   Filter `customer_journey = 'true'` AND `purpose = 'main'` — both mandatory together with `business_context = 'forRent'`
    
*   Read weights from `datalake_gsheets_clean.nps_target_share` with `customer_journey = 'TRUE'`
    
*   Use the most-recent-quarter fallback for months without a registered weight
    
*   Deduplicate weights with `ROW_NUMBER() OVER (PARTITION BY month, journey)` to protect against overlapping intervals in the GSheet
    
*   Compute NPS per journey separately before weighting
    

**Don't:**

*   Don't filter only on `business_context = 'forRent'` — this includes lost, ppm, po, and other journeys that do not compose NPS FR
    
*   Don't pool all answers directly — use the weighted calculation
    
*   Don't hardcode the weights (e.g. 25%, 53%, 22%) — always read from `nps_target_share`
    
*   Don't use `MAX` to aggregate `weight_source` — use `MIN` so that `'fallback'` shows up when any journey is missing an official weight
    

## Superset Golden Assets

*   **NPS For Rent Post Contract [Perf.] [Support and Services]** — reference dataset to use as the canonical base for NPS FR data manipulation in Superset.

## DataHub catalog

- **Data Product:** `urn:li:dataProduct:testing-nps-2`

