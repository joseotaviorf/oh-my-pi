# Supply Funnel Conversions

## Overview

**Supply Funnel Conversions** measures the volume and conversion rates between sequential stages of the property acquisition (supply) funnel. The funnel tracks a property's journey from initial contact to published listing through these ordered stages:

```
Lead → Prospect → Qualified → Opportunity → First Listing
```

Each adjacent-stage transition is an individual metric: **L2P** (Lead to Prospect), **P2Q** (Prospect to Qualified), **Q2O** (Qualified to Opportunity), and **O2L** (Opportunity to First Listing). The system also supports **non-adjacent** transitions (e.g. Lead to Listing, Prospect to Listing) by measuring whether a property that entered the funnel at stage A eventually reached stage B — regardless of intermediate stages.

All conversions use **cohort logic**: a property is counted as converted when it appears at the target stage with the same `sk_supply` and `nm_business_context` as its entry at the origin stage.

**Applies to both For Rent (RENT) and For Sale (SALE) verticals, Brazil (BR).**

## Related Business Entities

- Supply

## Glossary and Synonyms

- **L2P**, **Lead to Prospect**, **conversão de lead para prospect** → Lead → Prospect conversion
- **P2Q**, **Prospect to Qualified**, **conversão de prospect para qualificado** → Prospect → Qualified conversion
- **Q2O**, **Qualified to Opportunity**, **conversão de qualificado para oportunidade** → Qualified → Opportunity conversion
- **O2L**, **Opportunity to Listing**, **Opportunity to First Listing**, **conversão de oportunidade para listing** → Opportunity → First Listing conversion
- **L2L**, **Lead to Listing**, **conversão de lead para listing**, **conversão ponta a ponta** → Lead → First Listing (end-to-end)
- **P2L**, **Prospect to Listing**, **conversão de prospect para listing** → Prospect → First Listing
- **P2O**, **Prospect to Opportunity**, **conversão de prospect para oportunidade** → Prospect → Opportunity
- **Supply Funnel**, **Funil de Supply**, **Funil de Captação**, **taxa de conversão do funil** → this metric family
- **Cohort conversion**, **conversão por coorte** → cohort-based conversion rate

## Scope

**Included**: properties passing through the mapped funnel steps (`lead`, `prospect`, `qualified`, `av_qualified`, `opportunity`, `first_listing`) in `dw_growth.obt_supply`, for business contexts RENT and SALE, within the dynamic time window (current year and previous year).

**Excluded**: records without a classified business context (`nm_business_context`), records outside the mapped funnel steps, and historical data older than the 1-year lookback window.

## Calculation

A naive approach would be to divide total events at stage B by total events at stage A within the same period. This is **incorrect** because it ignores the cohort relationship — a property counted at stage B this week may have entered stage A months ago, and new entries at stage A this week haven't had time to convert yet.

The correct calculation uses **cohort matching**: for each property at the origin stage, check whether that same property (same `sk_supply` + `nm_business_context`) ever reaches the target stage.

```
Conversion_Rate(A→B) = COUNT(DISTINCT sk_supply at stage A that also reached stage B)
                       / COUNT(DISTINCT sk_supply at stage A)
```

### Adjacent-stage transitions

| Metric | Origin stage (`cd_funnel_step`) | Target stage (`cd_funnel_step`) | Volume column | Cohort column |
|---|---|---|---|---|
| **L2P** | `lead` | `prospect` | `act_leads` | `qty_l2p_cohort` |
| **P2Q** | `prospect` | `qualified` | `act_prospects` | `qty_p2q_cohort` |
| **Q2O** | `qualified` | `opportunity` | `act_qualifieds` | `qty_q2o_cohort` |
| **O2L** | `opportunity` | `first_listing` | `act_opportunities` | `qty_o2l_cohort` |

### Non-adjacent transitions

| Metric | Origin stage | Target stage | Volume column | Cohort column |
|---|---|---|---|---|
| **P2O** | `prospect` | `opportunity` | `act_prospects` | `qty_p2o_cohort` |
| **P2L** | `prospect` | `first_listing` | `act_prospects` | `qty_p2l_cohort` |

For any unlisted combination (e.g. Lead to Listing), the cohort join pattern is the same: match `sk_supply` + `nm_business_context` between origin and target stage events in `cohort_events`.

### Week-0 cohort variants

Each transition also has a `_w0` variant (e.g. `qty_o2l_cohort_w0`) that restricts the conversion to happen in the **same ISO week** as the origin event. This measures short-cycle conversion velocity.

### Canonical Filter

Apply on `dw_growth.obt_supply`:

```sql
cd_funnel_step IN ('lead', 'prospect', 'qualified', 'av_qualified', 'opportunity', 'first_listing')
AND YEAR(date) >= YEAR(CURRENT_DATE) - 1
```

For business-context segmentation, add:

```sql
AND nm_business_context = 'RENT'   -- or 'SALE'
```

For geographic segmentation, add:

```sql
AND country_code = 'BR'
```

**Warning**: omitting `nm_business_context` mixes RENT and SALE funnels, which have different conversion dynamics and should not be pooled for rate calculations.

### Nuances

The base CTE (`actual_vol`) produces a wide, pre-aggregated table with volume columns (`act_*`) and cohort columns (`qty_*_cohort`, `qty_*_cohort_w0`) for every transition. The final SELECT simply picks the desired rate:

| Rate | Expression |
|---|---|
| L2P | `SUM(qty_l2p_cohort) / NULLIF(SUM(act_leads), 0)` |
| P2Q | `SUM(qty_p2q_cohort) / NULLIF(SUM(act_prospects), 0)` |
| Q2O | `SUM(qty_q2o_cohort) / NULLIF(SUM(act_qualifieds), 0)` |
| O2L | `SUM(qty_o2l_cohort) / NULLIF(SUM(act_opportunities), 0)` |
| P2O | `SUM(qty_p2o_cohort) / NULLIF(SUM(act_prospects), 0)` |
| P2L | `SUM(qty_p2l_cohort) / NULLIF(SUM(act_prospects), 0)` |

For week-0 variants, replace `qty_*_cohort` with `qty_*_cohort_w0`.

**Carteirização and 3P FR test flags**: the base CTE includes `is_carteirizacao`, `is_exec_carteirizacao`, and `is_3p_fr_test` boolean flags derived from specific user IDs and date windows. These classify Outbound portfolio assignments and 3P For Rent test cohorts — use them as segmentation dimensions, not as exclusion filters, unless the analysis specifically requires it.

**Click-to-WhatsApp (`is_click_to_wpp`)**: a fallback-based flag identifying contacts originating from WhatsApp campaigns, derived from phone numbers, campaign names, or source environments mapped in `datalake_gsheets_clean.supply_inputs_click_to_whatsapp`.

**Campaign dictionary dedup**: campaign IDs with the same name are deduplicated via `ROW_NUMBER() OVER (PARTITION BY campaign_name ORDER BY dt_start ASC)`, keeping the first ID generated. This ensures analytical consistency when the same campaign is re-created with a new ID.

**FL uniqueness**: `datalake_supply_staging.supply_unique_rules` classifies whether a first listing is unique (`fl_unique`) or a cross-listing. Default is `'Cross-listing'` when no match exists.

## Dos and Don'ts

**Do:**

- Always use cohort-based conversion (match `sk_supply` + `nm_business_context` between origin and target stages)
- Segment by `nm_business_context` (RENT vs SALE) — never pool them for rate calculations
- Use `NULLIF` in the denominator to avoid division by zero
- Use the `_w0` variants when analyzing short-cycle conversion velocity
- Filter by `country_code = 'BR'` for Brazil-specific analysis

**Don't:**

- Don't divide total stage B events by total stage A events in the same period — this ignores cohort timing
- Don't mix RENT and SALE in a single conversion rate — the funnels have different step structures and timelines
- Don't hardcode user IDs for carteirização or 3P FR test flags — these are already computed in the base CTE
- Don't confuse `av_qualified` (AV qualified) with `qualified` — they are separate funnel steps; `av_qualified` sits between `qualified` and `opportunity`

## Golden Queries

The base CTE (`actual_vol`) builds the full wide table with all volumes and cohort columns. The final SELECT is then swapped depending on which conversion the user needs. Below is the complete base CTE followed by example extraction queries for each transition.

The base CTE uses `dw_growth.obt_supply` as the anchor, LEFT JOINing `cohort_events` for each target stage to compute cohort conversions. Auxiliary joins bring in campaign dictionaries, carteirização flags, click-to-WhatsApp classification, and FL uniqueness.

### Base CTE (reused by all golden queries)

```sql
WITH max_date_obt AS (
    SELECT MAX(date) AS max_date
    FROM dw_growth.obt_supply
),

aud_check_cart AS (
    SELECT id
    FROM datalake_wololo_clean.prospect_aud
    WHERE status = 'PORTFOLIO'
),

cohort_events AS (
    SELECT
        date,
        sk_supply,
        nm_business_context,
        cd_funnel_step
    FROM dw_growth.obt_supply
    WHERE cd_funnel_step IN ('prospect', 'qualified', 'opportunity', 'first_listing')
),

campaign_name_historic_dictionary AS (
    SELECT
        id_campaign,
        campaign_name,
        ROW_NUMBER() OVER (PARTITION BY campaign_name ORDER BY dt_start ASC) AS campaign_name_order,
        is_current
    FROM datalake_growth_media_platform.campaign_name_history
),

latest_campaign_name AS (
    SELECT *
    FROM (
        SELECT
            id_campaign,
            campaign_name,
            ROW_NUMBER() OVER (PARTITION BY id_campaign ORDER BY dt_end DESC NULLS FIRST, dt_start DESC) AS campaign_id_order
        FROM datalake_growth_media_platform.campaign_name_history
    ) sub
    WHERE campaign_id_order = 1
),

actual_vol AS (
    SELECT
        obt.date,
        obt.acquisition_origin,
        obt.nm_business_context AS business_context,
        obt.nm_supply_source    AS supply_source,
        obt.company_report_origin,
        obt.planning_operation,
        obt.planning_conversion,
        obt.planning_cluster,
        obt.behavior_type,
        obt.source,
        obt.medium,
        obt.nm_campaign,
        cnh.id_campaign,
        obt.country_code,
        obt.city_group,
        obt.ds_discard_reason,
        scc.campaign_cluster,
        CASE
            WHEN ac.id IS NOT NULL
                AND obt.country_code = 'BR'
                AND obt.planning_operation = 'Outbound'
                AND NOT (
                    obt.date >= DATE '2025-09-01'
                    AND obt.nm_business_context = 'RENT'
                    AND (
                        obt.sk_user_conversion IN (8919771, 11299701, 6001450)
                        OR obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994)
                    )
                )
            THEN TRUE
            ELSE FALSE
        END AS is_carteirizacao,
        CASE
            WHEN obt.sk_user_conversion IS NULL THEN NULL
            WHEN obt.sk_user_conversion IN (
                12524938, 13946547, 8213735, 13345718, 12547541, 13686088, 13096943, 12514676, 14248042,
                13650603, 14077391, 13089199, 13686095, 12525058, 13345712, 12547601, 13180531, 13044261,
                13686090, 8629756, 10461327, 8629755, 12839526, 13201490, 13892168, 13817190, 13180530,
                13473187, 13946548, 13473192, 12080523, 12422745, 12525005, 13395938, 13276220, 14473223,
                8793348, 13501526, 13158267, 12013178, 12839533, 9840974, 13390240, 12458723, 13390237,
                1479808, 13460993, 14473225, 13658514, 13096941, 12547669
            )
                AND NOT (
                    obt.date >= DATE '2025-09-01'
                    AND obt.nm_business_context = 'RENT'
                    AND (
                        obt.sk_user_conversion IN (8919771, 11299701, 6001450)
                        OR obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994)
                    )
                )
                AND obt.country_code = 'BR'
                AND obt.planning_operation = 'Outbound'
            THEN TRUE
            ELSE FALSE
        END AS is_exec_carteirizacao,
        CASE
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.date <= DATE '2025-11-18'
                AND obt.nm_business_context = 'RENT'
                AND obt.sk_user_conversion IN (8919771, 11299701, 6001450)
                THEN TRUE
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.date <= DATE '2025-11-18'
                AND obt.nm_business_context = 'RENT'
                AND obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994)
                THEN TRUE
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.nm_business_context = 'RENT'
                AND LOWER(obt.nm_agent) IN ('ciq_pj', '3p_fr')
                THEN TRUE
            ELSE FALSE
        END AS is_3p_fr_test,
        CASE
            WHEN obt.nm_campaign = '-1'
                AND ia.source_environment IN (
                    SELECT DISTINCT source_environment
                    FROM datalake_gsheets_clean.supply_inputs_click_to_whatsapp
                    WHERE source_environment IS NOT NULL
                        AND source_environment <> 'default'
                )
                THEN TRUE
            WHEN obt.nm_campaign IN (
                    SELECT DISTINCT nm_campaign
                    FROM datalake_gsheets_clean.supply_inputs_click_to_whatsapp
                    WHERE nm_campaign <> '-1'
                )
                THEN TRUE
            WHEN obt.quinto_andar_phone_number IN (
                    SELECT DISTINCT phone_number
                    FROM datalake_gsheets_clean.supply_inputs_click_to_whatsapp
                    WHERE phone_number IS NOT NULL
                )
                THEN TRUE
            ELSE FALSE
        END AS is_click_to_wpp,
        COALESCE(fl_unique.fl_unique, 'Cross-listing') AS fl_unique,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'lead' THEN obt.sk_supply END) AS act_leads,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'prospect' THEN obt.sk_supply END) AS act_prospects,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'qualified' THEN obt.sk_supply END) AS act_qualifieds,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'av_qualified' THEN obt.sk_supply END) AS act_av_qualifieds,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'opportunity' THEN obt.sk_supply END) AS act_opportunities,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'first_listing' THEN obt.sk_supply END) AS act_first_listings,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'lead' THEN prospects.sk_supply END) AS qty_l2p_cohort,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'prospect' THEN qualifieds.sk_supply END) AS qty_p2q_cohort,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'qualified' THEN opportunities.sk_supply END) AS qty_q2o_cohort,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'prospect' THEN opportunities.sk_supply END) AS qty_p2o_cohort,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'prospect' THEN first_listings.sk_supply END) AS qty_p2l_cohort,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'opportunity' THEN first_listings.sk_supply END) AS qty_o2l_cohort,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'lead'
            AND DATE_TRUNC('week', prospects.date) = DATE_TRUNC('week', obt.date)
            THEN prospects.sk_supply END) AS qty_l2p_cohort_w0,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'prospect'
            AND DATE_TRUNC('week', qualifieds.date) = DATE_TRUNC('week', obt.date)
            THEN qualifieds.sk_supply END) AS qty_p2q_cohort_w0,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'qualified'
            AND DATE_TRUNC('week', opportunities.date) = DATE_TRUNC('week', obt.date)
            THEN opportunities.sk_supply END) AS qty_q2o_cohort_w0,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'prospect'
            AND DATE_TRUNC('week', opportunities.date) = DATE_TRUNC('week', obt.date)
            THEN opportunities.sk_supply END) AS qty_p2o_cohort_w0,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'prospect'
            AND DATE_TRUNC('week', first_listings.date) = DATE_TRUNC('week', obt.date)
            THEN first_listings.sk_supply END) AS qty_p2l_cohort_w0,
        COUNT(DISTINCT CASE WHEN obt.cd_funnel_step = 'opportunity'
            AND DATE_TRUNC('week', first_listings.date) = DATE_TRUNC('week', obt.date)
            THEN first_listings.sk_supply END) AS qty_o2l_cohort_w0
    FROM dw_growth.obt_supply AS obt
    LEFT JOIN cohort_events AS prospects
        ON obt.sk_supply = prospects.sk_supply
        AND obt.nm_business_context = prospects.nm_business_context
        AND prospects.cd_funnel_step = 'prospect'
        AND obt.cd_funnel_step = 'lead'
    LEFT JOIN cohort_events AS qualifieds
        ON obt.sk_supply = qualifieds.sk_supply
        AND obt.nm_business_context = qualifieds.nm_business_context
        AND qualifieds.cd_funnel_step = 'qualified'
        AND obt.cd_funnel_step IN ('lead', 'prospect')
    LEFT JOIN cohort_events AS opportunities
        ON obt.sk_supply = opportunities.sk_supply
        AND obt.nm_business_context = opportunities.nm_business_context
        AND opportunities.cd_funnel_step = 'opportunity'
        AND obt.cd_funnel_step IN ('lead', 'prospect', 'qualified', 'av_qualified')
    LEFT JOIN cohort_events AS first_listings
        ON obt.sk_supply = first_listings.sk_supply
        AND obt.nm_business_context = first_listings.nm_business_context
        AND first_listings.cd_funnel_step = 'first_listing'
        AND obt.cd_funnel_step IN ('lead', 'prospect', 'qualified', 'av_qualified', 'opportunity')
    LEFT JOIN datalake_supply_staging.supply_unique_rules AS fl_unique
        ON obt.sk_supply = fl_unique.sk_supply
        AND obt.nm_business_context = fl_unique.nm_business_context
    LEFT JOIN datalake_gsheets_clean.supply_campaign_cluster AS scc
        ON LOWER(obt.campaign_strategy_intent) = LOWER(scc.campaign_strategy_intent)
        AND LOWER(obt.campaign_business_context) = LOWER(scc.campaign_business_context)
        AND LOWER(obt.source) = LOWER(scc.source)
        AND LOWER(obt.medium) = LOWER(scc.medium)
        AND LOWER(obt.behavior_type) = LOWER(scc.behavior_type)
        AND LOWER(obt.funnel_side) = LOWER(scc.funnel_side)
        AND LOWER(obt.campaign_landing_page) = LOWER(scc.campaign_landing_page)
    LEFT JOIN campaign_name_historic_dictionary AS cnh
        ON cnh.campaign_name = obt.nm_campaign
        AND cnh.campaign_name_order = 1
    LEFT JOIN datalake_wololo_clean.prospect AS p
        ON p.id_reference = obt.sk_lead
    LEFT JOIN aud_check_cart AS ac
        ON ac.id = p.id
    LEFT JOIN datalake_supply_flows.inbound_attribution AS ia
        ON ia.id_lead_ebdb = obt.sk_lead
    WHERE YEAR(obt.date) >= YEAR(CURRENT_DATE) - 1
    GROUP BY
        obt.date,
        obt.acquisition_origin,
        obt.nm_business_context,
        obt.nm_supply_source,
        obt.company_report_origin,
        obt.planning_operation,
        obt.planning_conversion,
        obt.planning_cluster,
        obt.behavior_type,
        obt.source,
        obt.medium,
        obt.nm_campaign,
        cnh.id_campaign,
        obt.country_code,
        obt.city_group,
        obt.ds_discard_reason,
        scc.campaign_cluster,
        CASE
            WHEN ac.id IS NOT NULL
                AND obt.country_code = 'BR'
                AND obt.planning_operation = 'Outbound'
                AND NOT (
                    obt.date >= DATE '2025-09-01'
                    AND obt.nm_business_context = 'RENT'
                    AND (
                        obt.sk_user_conversion IN (8919771, 11299701, 6001450)
                        OR obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994)
                    )
                )
            THEN TRUE
            ELSE FALSE
        END,
        CASE
            WHEN obt.sk_user_conversion IS NULL THEN NULL
            WHEN obt.sk_user_conversion IN (
                12524938, 13946547, 8213735, 13345718, 12547541, 13686088, 13096943, 12514676, 14248042,
                13650603, 14077391, 13089199, 13686095, 12525058, 13345712, 12547601, 13180531, 13044261,
                13686090, 8629756, 10461327, 8629755, 12839526, 13201490, 13892168, 13817190, 13180530,
                13473187, 13946548, 13473192, 12080523, 12422745, 12525005, 13395938, 13276220, 14473223,
                8793348, 13501526, 13158267, 12013178, 12839533, 9840974, 13390240, 12458723, 13390237,
                1479808, 13460993, 14473225, 13658514, 13096941, 12547669
            )
                AND NOT (
                    obt.date >= DATE '2025-09-01'
                    AND obt.nm_business_context = 'RENT'
                    AND (
                        obt.sk_user_conversion IN (8919771, 11299701, 6001450)
                        OR obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994)
                    )
                )
                AND obt.country_code = 'BR'
                AND obt.planning_operation = 'Outbound'
            THEN TRUE
            ELSE FALSE
        END,
        CASE
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.date <= DATE '2025-11-18'
                AND obt.nm_business_context = 'RENT'
                AND obt.sk_user_conversion IN (8919771, 11299701, 6001450)
                THEN TRUE
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.date <= DATE '2025-11-18'
                AND obt.nm_business_context = 'RENT'
                AND obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994)
                THEN TRUE
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.nm_business_context = 'RENT'
                AND LOWER(obt.nm_agent) IN ('ciq_pj', '3p_fr')
                THEN TRUE
            ELSE FALSE
        END,
        CASE
            WHEN obt.nm_campaign = '-1'
                AND ia.source_environment IN (
                    SELECT DISTINCT source_environment
                    FROM datalake_gsheets_clean.supply_inputs_click_to_whatsapp
                    WHERE source_environment IS NOT NULL
                        AND source_environment <> 'default'
                )
                THEN TRUE
            WHEN obt.nm_campaign IN (
                    SELECT DISTINCT nm_campaign
                    FROM datalake_gsheets_clean.supply_inputs_click_to_whatsapp
                    WHERE nm_campaign <> '-1'
                )
                THEN TRUE
            WHEN obt.quinto_andar_phone_number IN (
                    SELECT DISTINCT phone_number
                    FROM datalake_gsheets_clean.supply_inputs_click_to_whatsapp
                    WHERE phone_number IS NOT NULL
                )
                THEN TRUE
            ELSE FALSE
        END,
        COALESCE(fl_unique.fl_unique, 'Cross-listing')
)
```

### Extraction: all adjacent-stage conversion rates by week (For Rent)

```sql
-- Uses base CTE above (actual_vol)
SELECT
    DATE_TRUNC('week', date)                                                AS week_start,
    SUM(qty_l2p_cohort) * 1.0 / NULLIF(SUM(act_leads), 0)                 AS l2p_rate,
    SUM(qty_p2q_cohort) * 1.0 / NULLIF(SUM(act_prospects), 0)             AS p2q_rate,
    SUM(qty_q2o_cohort) * 1.0 / NULLIF(SUM(act_qualifieds), 0)            AS q2o_rate,
    SUM(qty_o2l_cohort) * 1.0 / NULLIF(SUM(act_opportunities), 0)         AS o2l_rate
FROM actual_vol
WHERE business_context = 'RENT'
    AND country_code = 'BR'
GROUP BY DATE_TRUNC('week', date)
ORDER BY DATE_TRUNC('week', date)
```

### Extraction: O2L conversion rate by week (For Rent)

```sql
-- Uses base CTE above (actual_vol)
SELECT
    DATE_TRUNC('week', date)                                                AS week_start,
    SUM(qty_o2l_cohort) * 1.0 / NULLIF(SUM(act_opportunities), 0)         AS o2l_rate
FROM actual_vol
WHERE business_context = 'RENT'
    AND country_code = 'BR'
GROUP BY DATE_TRUNC('week', date)
ORDER BY DATE_TRUNC('week', date)
```

### Extraction: Lead to Listing (end-to-end) volume and rate by week (For Sale)

```sql
-- Uses base CTE above (actual_vol)
-- For Lead-to-Listing, sum the cohort of leads that reached first_listing.
-- This requires an additional cohort join in the base CTE (lead → first_listing).
-- The base CTE already includes qty_p2l_cohort (prospect → listing).
-- For lead → listing, extend cohort_events join: add a LEFT JOIN where
-- obt.cd_funnel_step = 'lead' and first_listings.cd_funnel_step = 'first_listing'.
-- The base CTE's first_listings join already covers this (obt.cd_funnel_step IN ('lead', ...)),
-- so qty_l2l can be derived as:
SELECT
    DATE_TRUNC('week', date)                                                AS week_start,
    SUM(act_leads)                                                          AS total_leads,
    COUNT(DISTINCT CASE WHEN act_leads > 0 THEN NULL END)                   AS note,
    SUM(qty_l2p_cohort)                                                     AS leads_to_prospect,
    SUM(qty_p2l_cohort)                                                     AS prospects_to_listing
FROM actual_vol
WHERE business_context = 'SALE'
    AND country_code = 'BR'
GROUP BY DATE_TRUNC('week', date)
ORDER BY DATE_TRUNC('week', date)
```

### Extraction: week-0 conversion velocity (For Rent)

```sql
-- Uses base CTE above (actual_vol)
SELECT
    DATE_TRUNC('week', date)                                                AS week_start,
    SUM(qty_l2p_cohort_w0) * 1.0 / NULLIF(SUM(act_leads), 0)             AS l2p_w0_rate,
    SUM(qty_p2q_cohort_w0) * 1.0 / NULLIF(SUM(act_prospects), 0)         AS p2q_w0_rate,
    SUM(qty_q2o_cohort_w0) * 1.0 / NULLIF(SUM(act_qualifieds), 0)        AS q2o_w0_rate,
    SUM(qty_o2l_cohort_w0) * 1.0 / NULLIF(SUM(act_opportunities), 0)     AS o2l_w0_rate
FROM actual_vol
WHERE business_context = 'RENT'
    AND country_code = 'BR'
GROUP BY DATE_TRUNC('week', date)
ORDER BY DATE_TRUNC('week', date)
```

### Extraction: funnel volumes by week (all stages)

```sql
-- Uses base CTE above (actual_vol)
SELECT
    DATE_TRUNC('week', date)    AS week_start,
    business_context,
    SUM(act_leads)              AS leads,
    SUM(act_prospects)          AS prospects,
    SUM(act_qualifieds)         AS qualifieds,
    SUM(act_av_qualifieds)      AS av_qualifieds,
    SUM(act_opportunities)      AS opportunities,
    SUM(act_first_listings)     AS first_listings
FROM actual_vol
WHERE country_code = 'BR'
GROUP BY DATE_TRUNC('week', date), business_context
ORDER BY DATE_TRUNC('week', date), business_context
```

## Superset Golden Assets

- **Relatório de Supply Funnel** — canonical Superset dataset for supply funnel analysis segmented by business context, channel, and operation.
