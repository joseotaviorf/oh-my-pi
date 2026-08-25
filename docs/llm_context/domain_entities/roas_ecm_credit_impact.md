# ROAS / ECM Credit Impact

## Ownership

**Data Owner:**
- vinicius.araujo@quintoandar.com.br

**Data Steward:**
- vinicius.araujo@quintoandar.com.br

## Overview

Analytical frame for measuring whether a new **eCM / ELTV** model — used by the ROAS API to send conversion values to paid media — improves **credit quality** of acquired Tenant Prospects (TPs) without hurting volume.

**Production flow:** each **Visit Booked (VB)** or **Offer Submitted (OS)** triggers the **ROAS API**, which calls **EMLIO** (`id_service = 'eltv'`). EMLIO persists logs in `datalake_emlio_clean.emlio_logs`; the enrich table is `datalake_expected_contribution_margin.expected_contribution_margin` (`ecm`).

The new version of the model now also incorporates "Early Credit" features as input—a product offered to customers allowing them to undergo a preliminary credit assessment (which would otherwise take place later) to gauge their eligibility for the property.

Phase 1: the **Porto Alegre** receives `ecm_version = 'v3'` after cutover on **July 1, 2026**; comparable control cities stay on `v2` (**Belo Horizonte**, **RMSP** and **Rio de Janeiro**).
Phase 2: the **Campinas** receives `ecm_version = 'v3'` after cutover on **July 20, 2026**; comparable control cities stay on `v2` (**Belo Horizonte**, **RMSP** and **Rio de Janeiro**).

## Glossary and Synonyms

- **ROAS API** → invoked on each VB/OS; calls EMLIO; forwards `estimated_contribution_margin` to ad platforms
- **eCM / ELTV** → model-projected margin per inference; column `estimated_contribution_margin` on `ecm`
- **ecm_version** → model config tag per inference: `v3` = new credit-aware model (POA post-cutover); `v2` = prior config. Confirm with cutover date — do not use as sole time proxy
- **Cidade tratamento** → **Porto Alegre** and **Campinas** receives `v3` after their respective rollout
- **Cidade comparável** → control city for **all tiers**, same pre/post windows as rollouted cities. Controls: **Belo Horizonte**, **RMSP** and **Rio de Janeiro** (all remain on `v2`)
- **Early credit**, **crédito antecipado** → pre-offer screening; inputs in `ecm.request`, fallback `ecm.features` when request fields are null
- **Final credit** → post-OA proposal screening; `credit_analysis` + `fact_proposal_credit_flows`
- **Mix de crédito** → always state **which funnel**: Early Credit (Tier 1) vs Final Evaluation (Tier 2); use **`risk_category`** (macro bucket), not `risk_category_canon`
- **risk_category** → macro Sorting Hat credit risk score bucket (A, B, C, …); **this project's mix metric**.
- **risk_category_canon** → granular bucket (A1, A2, A3, …); finer policy label — **out of scope** for this ROAS read unless explicitly requested
- **Guarantee mix** → % share by guarantee bucket; raw source differs by funnel — see [Guarantee display labels](#guarantee-display-labels)
- **TP** → tenant prospect (`id_user` / `sk_client`) — ROAS API trigger at VB/OS; for **Tier 3 Growth reads**, TP is the same entity as **Prospect** (VB = visit booked, OS = offer sent)
- **ToF** (Top of Funnel) → user reaching Search, Listing, or Schedule page; `tof_users` in `growth_demand_performance_*`
- **Prospect** (Growth) → user who schedules a visit or submits an offer; `new_prospects + recovered_prospects` — see [`seo.md`](seo.md)
- **Paid Search** (Tier 2 + Tier 3 channel slice) → `medium IN ('SEM non-branded', 'Performance Max', 'Web Display')`. Tier 3: native in `growth_demand_performance_*`. Tier 2: attribute via `pcf` → `fact_demand_prospect_events` (`OFFER SUBMITTED`) → `dim_media_setup` — see [Conversion metrics (Tier 2)](#conversion-metrics-tier-2).
- **ToF2Prospect** → `SUM(new_prospects + recovered_prospects) / SUM(tof_users)` — use `tof_users`, not `tof_events`
- **ES2CA / OA2CS / OA2ES / ES2EP / EP2DS / DS2CA / CA2CS** → credit conversion rates on `pcf`; see [Conversion metrics (Tier 2)](#conversion-metrics-tier-2).

## Metric tiers

| Tier | Question | Metrics |
|------|----------|---------|
| **1 — Model** | What does the model change after rollout? | **Output:** sum/mean `estimated_contribution_margin`, call volume. **Early Credit inputs:** % by request `risk_category`; % by `result` |
| **2 — Credit** | Did Paid Search–acquired TPs pass credit better? | **ES2CA** (primary); **OA2CS** + sub-stages **OA2ES**, **ES2EP**, **EP2DS**, **DS2CA**, **CA2CS** (secondary); final **`risk_category`** mix; **`guarantee_offered`** share mix — **Paid Search slice** (ROAS-impacted audience) |
| **3 — Growth** | Did paid top-of-funnel acquisition break? | **Prospects** volume; **ToF2Prospect** rate; **R$/TP** (cost per prospect) — Paid Search slice only |

### Comparison strategy:

**Setup**: One treated city vs a small pool of comparable untreated cities, same pre/post windows. Document the calendar rollout date, the effective analysis cutover (first full post week), and any burn-in / mixed weeks to drop (partial exposure, ads platform lag, unfinished weeks). Pick a primary go/no-go metric; treat other metrics as supporting / health / mechanism only.

- Path A — Simple DiD (directional signal)
DiD = (Treated_post − Treated_pre) − (Controls_post − Controls_pre). Good for monitoring and early reads. Optionally recompute without the first post week if platforms are still oscillating. Language: suggestive only — never upgrade this alone into a causal claim.

- Path B — SDiD (recommended for causal claims)
Synthetic DiD on the baseline donor pool (cities with stable pre-period co-movement; exclude donors that break it). Trust the ATT only if: demeaned pre-fit looks OK, the real ATT sits outside the in-time placebo cloud and week-level ATTs are directionally stable.

### Model metrics (Tier 1)

- Read **`risk_category`** (macro) and guarantee **`result`** from `ecm.request` first.
- **Fallback:** when either field is null, read the same keys from `ecm.features` (`risk_category`, `result`).
- Share = `% of eCM API requests` (`COUNT(*)` on `expected_contribution_margin`, `id_service = 'eltv'`) per bucket, by **period** (pre/post cutover) and **`dim_region.city_group`** (via house join). **Denominator is always all requests** in the window — including rows without Early Credit fields.
- When **`risk_category`** is null in both `request` and `features`, bucket as **`s/early_credit`** for full-mix tables; **bar charts may omit this bucket** and show A–E as % of total, with the omitted share noted in the chart title (~80% in POA early monitoring).
- **Guarantee `result` mix:** same denominator rule — map to **FREE / PAID / CLEAR_NO** — see [Guarantee display labels](#guarantee-display-labels);
- **Early Credit logging start (POA):** fields first appear in `ecm.features` on **`2026-06-12`** (~20% of daily requests); before that date there is no Early Credit signal. For **mix and eCM-by-risk_category** reads, use **pre = 2026-06-12 through 2026-06-30**, not full June. From **`2026-07-01`** (v3 cutover) the same fields move to `ecm.request`.

### Conversion metrics (Tier 2)

#### Metric timing: coincident vs cohort
Both are valid; they answer different questions. Always confirm with the user which one they want before building queries or causal panels.

- Coincident: stage rates in a calendar window using each stage’s own date (not linked to an entry cohort). Typical base: dw_credit.fact_proposal_credit_flows (pcf), is_last_credit_evaluation = TRUE, rental_administrator = 'QUINTOANDAR', country_code = 'BR'. Rate = volume of the target stage in the period ÷ volume of the base stage in the period. Best for ad-hoc / managerial reads: fast, aligns with credit-committee style reporting, reflects what happened in that week. Downside: mix of cohorts and maturation can move the series for reasons unrelated to the treatment.

- Cohort: fix units by an entry date (always dt_offer_approved_date) and follow them forward. Best for experiment / causal analysis: more stable identification, less contamination from later-entering volume. Downside: needs enough maturation; early post weeks can look incomplete until cohorts age. Same base and filters as coincident; only the date logic changes (entry cohort vs each stage’s own date). 

Note: Consider a 5-day maturation window starting from the date of the approved offer as a good conversion window; by that point, over 99% of conversions have already occurred.

**Rule of thumb**: managerial snapshot → coincident (unless user says otherwise). Rollout impact / DiD–SDiD → cohort. If unclear, ask.

#### Metric, meaning and role

| Metric | Meaning | Role |
|--------|---------|------|
| **ES2CA** | Evaluation started → credit approved | **Primary metric, but longer maturation window for cohort analysis** |
| **OA2CS** | Offer approved → contract signed | **Secondary metric** — end-to-end from OA |
| **OA2ES** | Offer approved → evaluation started | **Secondary metric** - Sub-stage of OA2CS |
| **ES2EP** | Evaluation started → evaluation positive | **Secondary metric, but preferably as a primary if conducting a causal analysis within a cohort study** |
| **EP2DS** | Evaluation positive → documentation sent | **Secondary metric** - Sub-stage of OA2CS |
| **DS2CA** | Documentation sent → credit approved | **Secondary metric** - Sub-stage of OA2CS |
| **CA2CS** | Credit approved → contract signed | **Secondary metric** - Sub-stage of OA2CS |


#### Coincident stage dates and flags

| Metric | Numerator (date) | Denominator (date) |
|--------|------------------|---------------------|
| ES2CA | `dt_credit_analysis_approved_date` | `dt_last_credit_evaluation_init` |
| OA2CS | `dt_contract_signed_date` | `dt_offer_approved_date` |
| OA2ES | `dt_last_credit_evaluation_init` | `dt_offer_approved_date` |
| ES2EP | `ep_flag = 1` → `dt_credit_evaluation_approved_date` | `dt_last_credit_evaluation_init` |
| EP2DS | `dt_tenant_first_doc_sent_date` | `ep_flag = 1` → `dt_credit_evaluation_approved_date` |
| DS2CA | `dt_credit_analysis_approved_date` | `dt_tenant_first_doc_sent_date` |
| CA2CS | `dt_contract_signed_date` | `dt_credit_analysis_approved_date` |

### Growth metrics (Tier 3)

Top-of-funnel guardrails from the Growth department — same tables and definitions as [`seo.md`](seo.md). ROAS API spend maps to **paid** media; Tier 3 isolates the **Paid Search** slice the team uses for performance reads.

| Metric | Definition | Notes |
|--------|------------|-------|
| **Prospects** | `SUM(new_prospects + recovered_prospects)` | Absolute volume; `business_context = 'rent'` unless the read explicitly needs Sale |
| **ToF2Prospect** | `SUM(new_prospects + recovered_prospects) / CAST(SUM(tof_users) AS DOUBLE)` | Rate from ToF users to Prospect; **always** `tof_users` in the denominator, not `tof_events` |
| **R$/TP** (cost per prospect) | Paid Search media cost / Prospects in the same window | Same Demand-committee definition Growth uses; **TP = Prospect** here (VB + OS). Numerator from `fact_media_platform_metrics`; denominator from `growth_demand_performance_*` |

**Paid Search channel filter** — restrict `medium` to:

| `medium` value |
|----------------|
| `SEM non-branded` |
| `Performance Max` |
| `Web Display` |

**Source:** `metric_growth.growth_demand_performance_monthly` (or `_weekly` / `_daily` for finer grain — same column layout; date key = `dt_month_start` / `dt_week_start` / `dt_event`).

**R$/TP — media cost (numerator):** `dw_growth.fact_media_platform_metrics` joined to `dim_media_setup` (`funnel_side = 'demand'`, `campaign_business_context = 'rent'`, Paid Search `medium`, exclude `campaign_strategy_intent = 'Brand Awareness'`). Cost = `SUM(total_cost * COALESCE(share, 1))` with optional allocation via `dim_sharing_rules` when the campaign has no explicit region (`COALESCE(dim_region.city_group, dim_sharing_rules.city_group)` for geography).

### Paid Search slice 

**Paid Search** is the primary audience affected by the ROAS / ELTV change (ROAS API spend reaches Paid Search). For Tier 2 ROAS-style reads (conversions + final-credit mix) it remains a natural default slice when the question is specifically about that channel. For experiment / causal impact analysis, prefer all acquisition channels unless the user asks otherwise. That way results reflect the full credit-evaluation pipeline, not a sub-population that may misrepresent the overall operation.

Note: `pcf` has no `medium`; attribute each proposal once:

1. `CAST(pcf.sk_offer AS VARCHAR) = CAST(fdpe.sk_offer AS VARCHAR)`
2. `fdpe.business_context = 'rent'` and **`fdpe.event_name = 'OFFER SUBMITTED'`** (1:1 with OA; no `ROW_NUMBER` dedup needed)
3. `fdpe.naming_convention_sufix` → `dim_media_setup.medium`
4. Keep rows where `medium IN ('SEM non-branded', 'Performance Max', 'Web Display')`

`medium` NULL on `OFFER SUBMITTED` is expected — those proposals are **out of scope** for this product (not Paid Search). All-channel totals (no `fdpe` join) match credit committee reports and general impact on credit pipeline — use as a benchmark or when in causal analysis.

### Guarantee display labels

Query on raw source values; use these labels in mix charts and stakeholder reads:

| Display | Early Credit (`ecm.request` / `ecm.features` → `result`) | Final credit (`ca` / `pcf` → `guarantee_offered`) |
|---------|-----------------------------------------------------------|---------------------------------------------------|
| **FREE** | `FREE` | `FREE` |
| **PAID** | `PRO_GUARANTOR` | `PRO_GUARANTOR` |
| **CLEAR_NO** | `REJECTED` | `CLEAR_NO` |

Any other raw value (`DEPOSIT`, `STANDALONE`, `THIRD_PARTY_GUARANTEE`, …) — show **explicitly** under its source name; do not fold into PAID or CLEAR_NO.

When analyzing guarantee distribution, the funnel stage used as the anchor matters. 

In the final credit, if the anchor is a post-approval step (e.g., credit analysis approved, ca_flag = 1), only FREE and PRO_GUARANTOR will appear — CLEAR_NO cases never reach that stage. If an earlier step is used (e.g., evaluation started or offer submitted), all outcome categories appear; rows with a null guarantee should be excluded, as those proposals have not yet received a credit decision. One important caveat: FREE% appears higher under a post-approval anchor not because the model approves more tenants, but because CLEAR_NO cases are removed from the denominator. The two anchors measure different things and are not directly comparable.

In the Early Credit (model input), use % of **all** requests, not % among rows with `result` filled to also highlight the distribution of requests with customers that bypassed the Early Credit product. 


## Tables

| Need | Table |
|------|-------|
| ROAS inference logs | `datalake_expected_contribution_margin.expected_contribution_margin` (`ecm`) — `id_service = 'eltv'` |
| Final credit mix + conversions | `dw_credit.fact_proposal_credit_flows` (`pcf`) — base: `is_last_credit_evaluation = TRUE`, `rental_administrator = 'QUINTOANDAR'`, `country_code = 'BR'`; geo via `pcf.sk_region` → `dim_region.city_group` |
| Paid Search channel on proposals (Tier 2) | `dw_growth.fact_demand_prospect_events` (`fdpe`) — `event_name = 'OFFER SUBMITTED'`, join on `sk_offer`; `dw_growth.dim_media_setup` (`dms`) on `naming_convention_sufix` → `medium` |
| Final credit screening attributes | `datalake_credit_analysis.credit_analysis` (`ca`) |
| City slice on ECM (Tier 1) | `ecm.id_house` → `datalake_ebdb_clean.house` → `dw_public.dim_region` — filter **`dr.city_group`** |
| Growth ToF / Prospects (Tier 3) | `metric_growth.growth_demand_performance_monthly` (or `_weekly` / `_daily`) — filter `medium` for Paid Search |
| Paid media cost (Tier 3 R$/TP) | `dw_growth.fact_media_platform_metrics` + `dw_growth.dim_media_setup` + `dw_public.dim_region` + `dw_growth.dim_sharing_rules` (optional cost allocation) |

**Critical rules:**
- **DataHub CI:** primary dataset for this product: `datalake_expected_contribution_margin.expected_contribution_margin`. Other tables in this section are routing references owned by sibling entities — do not list them in `datasets`.
- **Tier 1:** filter **`dim_region.city_group`** + **cutover date** (pre/post).
- **Tier 2:** credit committee base on `pcf` — `is_last_credit_evaluation = TRUE`, `rental_administrator = 'QUINTOANDAR'`, `country_code = 'BR'`; filter **`dim_region.city_group`** via `pcf.sk_region` — same three values; **default Paid Search** via `pcf.sk_offer` → `fdpe` (`OFFER SUBMITTED`) → `dms.medium` (`SEM non-branded`, `Performance Max`, `Web Display`).
- **Tier 3:** filter **`city_group`** in `growth_demand_performance_*` and cost tables — same three values; slice **`medium`** to Paid Search (`SEM non-branded`, `Performance Max`, `Web Display`); default **`business_context = 'rent'`**; use **`tof_users`** for ToF2Prospect denominator — see [`seo.md`](seo.md). **R$/TP:** join cost and Prospects on the **same** `city_group` + time grain.
- **Tier 1:** `ecm` has full history — before/after on POA is valid; use `ecm_version` to sanity-check model config, not as sole time proxy.
- **`estimated_contribution_margin` is predicted** — not realized revenue.
- **Early vs Final mix:** Tier 1 = `ecm.request` with **`ecm.features` fallback**; Tier 2 = `ca` / `pcf`. Never swap them.

## Relationships

- **SEO / Growth demand** ([`seo.md`](seo.md)) — ToF, Prospects, `growth_demand_performance_*`, Paid Search `medium` taxonomy (Tier 3 volume and efficiency).
- **Fintech credit** — `pcf` + `credit_analysis`; coincident and cohort ES2CA / OA2CS sub-stages aligned with credit committee reports (Tier 2). **Paid Search attribution** — `fdpe` + `dim_media_setup` on `sk_offer`.

## Dos and Don'ts

**Do:**
- **All tiers:** before/after around POA cutover; add **comparable control cities** in the same pre/post windows; document both cutover date and city list.
- Use **ES2CA** as headline conversion; **OA2CS** and sub-stages **OA2ES**, **ES2EP**, **EP2DS**, **DS2CA**, **CA2CS** as secondary reads — **Paid Search slice** for ROAS managerial analysis and all-channels for causal impact analysis.
- Tier 3: track **Prospects** volume, **ToF2Prospect**, and **R$/TP** on the **Paid Search** `medium` slice alongside credit mix shifts.
- Filter `ecm.id_service = 'eltv'` for FR Rent ROAS.
- Parse `ecm.request` for Early Credit inputs; **fall back to `ecm.features`** when `risk_category` or `result` is null in request.

**Don't:**
- Don't slice Tier 1 eCM by **`features.city`** — use **`city_group`** via the house join.
- Don't slice Tier 2 or Tier 3 by **`city_name`** — use **`city_group`**.
- Don't treat `ecm_version` as a global time flag — anchor on **cutover date + geography key for the tier**.
- Don't use **final-credit** mix (`ca`, `pcf`) to answer Tier 1 model-input questions.
- Don't use **`metric_rent.cohort_conversions_volumes`** or **`fr_transact`** event-funnel tables for Tier 2 conversion rates; Prospects volume is Tier 3 via [`seo.md`](seo.md), not rent-flow stage counts.
- Don't filter Tier 2 `pcf` with **`is_user_version`** — credit committee reports use **`is_last_credit_evaluation`** (broader; includes multi-proposal users).
- Don't conflate **`risk_category`** (macro: A, B, C) with **`risk_category_canon`** (granular: A1, A2, A3) — this project tracks macro only.
- Don't use **`tof_events`** for ToF2Prospect — denominator is **`tof_users`** only ([`seo.md`](seo.md)).
- Don't mix organic and paid in Tier 3 — always filter the Paid Search `medium` set on credit reads (`fdpe` join) and Growth reads (`growth_demand_performance_*`); SEO branded/non-branded are out of scope for this ROAS read.
- Don't compute **R$/TP** with mismatched geographies — cost and Prospects must share the same `city_group` and time grain.

## Golden Queries

### Query 1 — Tier 1: eCM output + Early Credit input mix (before/after + comparable cities)

```sql
SELECT
    DATE_TRUNC('week', ecm.ts_event) AS dt_week,
    dr.city_group,
    CASE
        WHEN ecm.ts_event < TIMESTAMP '2026-07-01 00:00:00' THEN 'pre-launch'
        ELSE 'post-launch'
    END AS period,  -- POA rollout cutover
    ecm.ecm_version,
    COALESCE(
        json_extract_scalar(ecm.request, '$.risk_category'),
        json_extract_scalar(ecm.features, '$.risk_category')
    ) AS early_credit_risk_category,
    COALESCE(
        json_extract_scalar(ecm.request, '$.result'),
        json_extract_scalar(ecm.features, '$.result')
    ) AS early_credit_guarantee_result,
    COUNT(*) AS roas_api_calls,
    SUM(ecm.estimated_contribution_margin) AS total_reported_ecm,
    AVG(ecm.estimated_contribution_margin) AS avg_reported_ecm,
    AVG(ecm.estimated_default_probability) AS avg_default_prob
FROM datalake_expected_contribution_margin.expected_contribution_margin AS ecm
INNER JOIN datalake_ebdb_clean.house AS h
    ON ecm.id_house = h.id
INNER JOIN dw_public.dim_region AS dr
    ON h.id_region = dr.id
WHERE ecm.id_service = 'eltv'
  AND dr.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Rio de Janeiro', 'RMSP')
  AND ecm.year = 2026
  AND ecm.month >= 1
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY 1, 2, 3, 7 DESC
```

### Query 2 — Tier 2: Coincident ES2CA, OA2CS + sub-stages by city_group — Paid Search (primary ROAS read)

```sql
WITH offer_medium AS (
    SELECT
        CAST(fdpe.sk_offer AS VARCHAR) AS sk_offer,
        dms.medium
    FROM dw_growth.fact_demand_prospect_events AS fdpe
    INNER JOIN dw_growth.dim_media_setup AS dms
        ON fdpe.naming_convention_sufix = dms.naming_convention_sufix
    WHERE LOWER(fdpe.business_context) = 'rent'
      AND fdpe.event_name = 'OFFER SUBMITTED'
      AND dms.medium IN ('SEM non-branded', 'Performance Max', 'Web Display')
),

eligible AS (
    SELECT
        pcf.sk_proposal,
        dr.city_group,
        pcf.dt_offer_approved_date,
        pcf.dt_last_credit_evaluation_init,
        pcf.dt_credit_evaluation_approved_date,
        pcf.dt_tenant_first_doc_sent_date,
        pcf.dt_credit_analysis_approved_date,
        pcf.dt_contract_signed_date,
        pcf.ep_flag
    FROM dw_credit.fact_proposal_credit_flows AS pcf
    INNER JOIN dw_public.dim_region AS dr
        ON pcf.sk_region = dr.sk_region
    INNER JOIN offer_medium AS om
        ON CAST(pcf.sk_offer AS VARCHAR) = om.sk_offer
    WHERE pcf.is_last_credit_evaluation = TRUE
      AND pcf.rental_administrator = 'QUINTOANDAR'
      AND pcf.country_code = 'BR'
      AND NULLIF(pcf.sk_offer_approved_date, -1) IS NOT NULL
      AND NULLIF(pcf.sk_proposal, -1) IS NOT NULL
      AND dr.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Rio de Janeiro', 'RMSP')
),

stage_volumes AS (
    SELECT DATE_TRUNC('week', dt_offer_approved_date) AS dt_period, city_group, 'oa' AS stage, COUNT(*) AS qty
    FROM eligible WHERE dt_offer_approved_date IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_last_credit_evaluation_init), city_group, 'es', COUNT(*)
    FROM eligible WHERE dt_last_credit_evaluation_init IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_credit_evaluation_approved_date), city_group, 'ep', COUNT(*)
    FROM eligible WHERE ep_flag = 1 AND dt_credit_evaluation_approved_date IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_tenant_first_doc_sent_date), city_group, 'ds', COUNT(*)
    FROM eligible WHERE dt_tenant_first_doc_sent_date IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_credit_analysis_approved_date), city_group, 'ca', COUNT(*)
    FROM eligible WHERE dt_credit_analysis_approved_date IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_contract_signed_date), city_group, 'cs', COUNT(*)
    FROM eligible WHERE dt_contract_signed_date IS NOT NULL GROUP BY 1, 2
)

SELECT
    CAST(dt_period AS DATE) AS dt_week_start,
    city_group,
    ROUND(100.0 * SUM(CASE WHEN stage = 'ca' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'es' THEN qty END), 0) AS DOUBLE), 2) AS es2ca_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'cs' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'oa' THEN qty END), 0) AS DOUBLE), 2) AS oa2cs_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'es' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'oa' THEN qty END), 0) AS DOUBLE), 2) AS oa2es_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'ep' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'es' THEN qty END), 0) AS DOUBLE), 2) AS es2ep_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'ds' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'ep' THEN qty END), 0) AS DOUBLE), 2) AS ep2ds_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'ca' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'ds' THEN qty END), 0) AS DOUBLE), 2) AS ds2ca_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'cs' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'ca' THEN qty END), 0) AS DOUBLE), 2) AS ca2cs_rate_pct
FROM stage_volumes
WHERE dt_period >= DATE '2026-01-01'
GROUP BY 1, 2
ORDER BY 2, 1
```

### Query 2b — Tier 2: same rates, all-channel

```sql
WITH eligible AS (
    SELECT
        pcf.sk_proposal,
        dr.city_group,
        pcf.dt_offer_approved_date,
        pcf.dt_last_credit_evaluation_init,
        pcf.dt_credit_evaluation_approved_date,
        pcf.dt_tenant_first_doc_sent_date,
        pcf.dt_credit_analysis_approved_date,
        pcf.dt_contract_signed_date,
        pcf.ep_flag
    FROM dw_credit.fact_proposal_credit_flows AS pcf
    INNER JOIN dw_public.dim_region AS dr
        ON pcf.sk_region = dr.sk_region
    WHERE pcf.is_last_credit_evaluation = TRUE
      AND pcf.rental_administrator = 'QUINTOANDAR'
      AND pcf.country_code = 'BR'
      AND NULLIF(pcf.sk_offer_approved_date, -1) IS NOT NULL
      AND NULLIF(pcf.sk_proposal, -1) IS NOT NULL
      AND dr.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Rio de Janeiro', 'RMSP')
),

stage_volumes AS (
    SELECT DATE_TRUNC('week', dt_offer_approved_date) AS dt_period, city_group, 'oa' AS stage, COUNT(*) AS qty
    FROM eligible WHERE dt_offer_approved_date IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_last_credit_evaluation_init), city_group, 'es', COUNT(*)
    FROM eligible WHERE dt_last_credit_evaluation_init IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_credit_evaluation_approved_date), city_group, 'ep', COUNT(*)
    FROM eligible WHERE ep_flag = 1 AND dt_credit_evaluation_approved_date IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_tenant_first_doc_sent_date), city_group, 'ds', COUNT(*)
    FROM eligible WHERE dt_tenant_first_doc_sent_date IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_credit_analysis_approved_date), city_group, 'ca', COUNT(*)
    FROM eligible WHERE dt_credit_analysis_approved_date IS NOT NULL GROUP BY 1, 2
    UNION ALL
    SELECT DATE_TRUNC('week', dt_contract_signed_date), city_group, 'cs', COUNT(*)
    FROM eligible WHERE dt_contract_signed_date IS NOT NULL GROUP BY 1, 2
)

SELECT
    CAST(dt_period AS DATE) AS dt_week_start,
    city_group,
    ROUND(100.0 * SUM(CASE WHEN stage = 'ca' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'es' THEN qty END), 0) AS DOUBLE), 2) AS es2ca_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'cs' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'oa' THEN qty END), 0) AS DOUBLE), 2) AS oa2cs_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'es' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'oa' THEN qty END), 0) AS DOUBLE), 2) AS oa2es_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'ep' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'es' THEN qty END), 0) AS DOUBLE), 2) AS es2ep_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'ds' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'ep' THEN qty END), 0) AS DOUBLE), 2) AS ep2ds_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'ca' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'ds' THEN qty END), 0) AS DOUBLE), 2) AS ds2ca_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN stage = 'cs' THEN qty END)
        / CAST(NULLIF(SUM(CASE WHEN stage = 'ca' THEN qty END), 0) AS DOUBLE), 2) AS ca2cs_rate_pct
FROM stage_volumes
WHERE dt_period >= DATE '2026-01-01'
GROUP BY 1, 2
ORDER BY 2, 1
```

### Query 2c — Tier 2: cohort conversion, all-channel

```sql
WITH eligible AS (
    SELECT
        pcf.sk_proposal,
        dr.city_group,
        pcf.dt_offer_approved_date AS oa_date,
        pcf.es_flag,
        pcf.ep_flag,
        pcf.ds_flag,
        pcf.ca_flag,
        pcf.cs_flag
    FROM dw_credit.fact_proposal_credit_flows AS pcf
    INNER JOIN dw_public.dim_region AS dr
        ON pcf.sk_region = dr.sk_region
    WHERE
      pcf.is_last_credit_evaluation = TRUE
      AND pcf.rental_administrator = 'QUINTOANDAR'
      AND pcf.country_code = 'BR'
      AND NULLIF(pcf.sk_offer_approved_date, -1) IS NOT NULL
      AND NULLIF(pcf.sk_proposal, -1) IS NOT NULL
      AND dr.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Rio de Janeiro', 'RMSP')
)

SELECT
    CAST(DATE_TRUNC('week', oa_date) AS DATE) AS dt_cohort_week_start,
    city_group,
    CASE WHEN city_group = 'Porto Alegre' THEN 1 ELSE 0 END AS is_treated,
    CASE
        WHEN DATE_TRUNC('week', oa_date) >= DATE_TRUNC('week', DATE '2026-07-01')
        THEN 1 ELSE 0
    END AS is_post,  -- POA Phase 1 cutover; adjust per rollout
    COUNT(*) AS n_oa,
    SUM(es_flag) AS n_es,
    SUM(ep_flag) AS n_ep,
    SUM(ds_flag) AS n_ds,
    SUM(ca_flag) AS n_ca,
    SUM(cs_flag) AS n_cs,
    ROUND(
        100.0 * SUM(es_flag)
        / CAST(NULLIF(COUNT(*), 0) AS DOUBLE),
        2
    ) AS oa2es_pct,
    ROUND(
        100.0 * SUM(ep_flag)
        / CAST(NULLIF(SUM(es_flag), 0) AS DOUBLE),
        2
    ) AS es2ep_pct,
    ROUND(
        100.0 * SUM(ds_flag)
        / CAST(NULLIF(SUM(ep_flag), 0) AS DOUBLE),
        2
    ) AS ep2ds_pct,
    ROUND(
        100.0 * SUM(ca_flag)
        / CAST(NULLIF(SUM(ds_flag), 0) AS DOUBLE),
        2
    ) AS ds2ca_pct,
    ROUND(
        100.0 * SUM(cs_flag)
        / CAST(NULLIF(SUM(ca_flag), 0) AS DOUBLE),
        2
    ) AS ca2cs_pct,
    ROUND(
        100.0 * SUM(ca_flag)
        / CAST(NULLIF(SUM(es_flag), 0) AS DOUBLE),
        2
    ) AS es2ca_pct,
    ROUND(
        100.0 * SUM(cs_flag)
        / CAST(NULLIF(COUNT(*), 0) AS DOUBLE),
        2
    ) AS oa2cs_pct
FROM eligible
WHERE oa_date >= DATE '2026-01-01'
  AND oa_date < DATE '2026-10-01'
GROUP BY 1, 2, 3, 4
ORDER BY 2, 1
```

### Query 3 — Tier 2: final credit mix by risk_category (macro) — Paid Search

```sql
WITH offer_medium AS (
    SELECT CAST(fdpe.sk_offer AS VARCHAR) AS sk_offer
    FROM dw_growth.fact_demand_prospect_events AS fdpe
    INNER JOIN dw_growth.dim_media_setup AS dms
        ON fdpe.naming_convention_sufix = dms.naming_convention_sufix
    WHERE LOWER(fdpe.business_context) = 'rent'
      AND fdpe.event_name = 'OFFER SUBMITTED'
      AND dms.medium IN ('SEM non-branded', 'Performance Max', 'Web Display')
),

paid_search_proposals AS (
    SELECT DISTINCT pcf.sk_proposal
    FROM dw_credit.fact_proposal_credit_flows AS pcf
    INNER JOIN offer_medium AS om
        ON CAST(pcf.sk_offer AS VARCHAR) = om.sk_offer
    WHERE pcf.is_last_credit_evaluation = TRUE
      AND pcf.rental_administrator = 'QUINTOANDAR'
      AND pcf.country_code = 'BR'
      AND NULLIF(pcf.sk_offer_approved_date, -1) IS NOT NULL
      AND NULLIF(pcf.sk_proposal, -1) IS NOT NULL
),

first_screening AS (
    SELECT
        ca.id_proposal,
        ca.risk_category,
        ca.ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY ca.id_proposal
            ORDER BY ca.ts_created ASC
        ) AS rni
    FROM datalake_credit_analysis.credit_analysis AS ca
    INNER JOIN paid_search_proposals AS psp
        ON ca.id_proposal = psp.sk_proposal
    WHERE ca.risk_category IS NOT NULL
)
SELECT
    DATE_TRUNC('month', fs.ts_created) AS dt_month,
    fs.risk_category,
    COUNT(DISTINCT fs.id_proposal) AS proposals,
    ROUND(
        100.0 * COUNT(DISTINCT fs.id_proposal)
        / CAST(SUM(COUNT(DISTINCT fs.id_proposal)) OVER (PARTITION BY DATE_TRUNC('month', fs.ts_created)) AS DOUBLE),
        2
    ) AS share_pct
FROM first_screening AS fs
WHERE fs.rni = 1
  AND fs.ts_created >= TIMESTAMP '2026-01-01 00:00:00'
GROUP BY 1, 2
ORDER BY 1, share_pct DESC
```

### Query 4 — Tier 2: guarantee mix by `guarantee_offered` (full share) — Paid Search

```sql
WITH offer_medium AS (
    SELECT CAST(fdpe.sk_offer AS VARCHAR) AS sk_offer
    FROM dw_growth.fact_demand_prospect_events AS fdpe
    INNER JOIN dw_growth.dim_media_setup AS dms
        ON fdpe.naming_convention_sufix = dms.naming_convention_sufix
    WHERE LOWER(fdpe.business_context) = 'rent'
      AND fdpe.event_name = 'OFFER SUBMITTED'
      AND dms.medium IN ('SEM non-branded', 'Performance Max', 'Web Display')
),

paid_search_proposals AS (
    SELECT DISTINCT pcf.sk_proposal
    FROM dw_credit.fact_proposal_credit_flows AS pcf
    INNER JOIN offer_medium AS om
        ON CAST(pcf.sk_offer AS VARCHAR) = om.sk_offer
    WHERE pcf.is_last_credit_evaluation = TRUE
      AND pcf.rental_administrator = 'QUINTOANDAR'
      AND pcf.country_code = 'BR'
      AND NULLIF(pcf.sk_offer_approved_date, -1) IS NOT NULL
      AND NULLIF(pcf.sk_proposal, -1) IS NOT NULL
),

first_screening AS (
    SELECT
        ca.id_proposal,
        ca.guarantee_offered,
        ca.ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY ca.id_proposal
            ORDER BY ca.ts_created ASC
        ) AS rni
    FROM datalake_credit_analysis.credit_analysis AS ca
    INNER JOIN paid_search_proposals AS psp
        ON ca.id_proposal = psp.sk_proposal
    WHERE ca.guarantee_offered IS NOT NULL
)
SELECT
    DATE_TRUNC('month', fs.ts_created) AS dt_month,
    fs.guarantee_offered,
    COUNT(DISTINCT fs.id_proposal) AS proposals,
    ROUND(
        100.0 * COUNT(DISTINCT fs.id_proposal)
        / CAST(SUM(COUNT(DISTINCT fs.id_proposal)) OVER (PARTITION BY DATE_TRUNC('month', fs.ts_created)) AS DOUBLE),
        2
    ) AS share_pct
FROM first_screening AS fs
WHERE fs.rni = 1
  AND fs.ts_created >= TIMESTAMP '2026-01-01 00:00:00'
GROUP BY 1, 2
ORDER BY 1, share_pct DESC
```

### Query 5 — Tier 3: Paid Search Prospects and ToF2Prospect by city (`growth_demand_performance`)

Paid Search = `SEM non-branded` + `Performance Max` + `Web Display`. Same pattern on `growth_demand_performance_weekly` (`dt_week_start`) or `_daily` (`dt_event`).

```sql
SELECT
    gdp.dt_month_start,
    gdp.city_group,
    CASE
        WHEN gdp.dt_month_start < DATE '2026-07-01' THEN 'pre'
        ELSE 'post'
    END AS period,
    SUM(gdp.new_prospects + gdp.recovered_prospects) AS prospects,
    SUM(gdp.tof_users) AS tof_users,
    ROUND(
        100.0 * SUM(gdp.new_prospects + gdp.recovered_prospects)
        / CAST(NULLIF(SUM(gdp.tof_users), 0) AS DOUBLE),
        2
    ) AS tof_2_prospect_pct
FROM metric_growth.growth_demand_performance_monthly AS gdp
WHERE gdp.country_code = 'BR'
  AND LOWER(gdp.business_context) = 'rent'
  AND gdp.medium IN ('SEM non-branded', 'Performance Max', 'Web Display')
  AND gdp.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Rio de Janeiro', 'RMSP')
  AND gdp.dt_month_start >= DATE '2026-01-01'
GROUP BY 1, 2, 3
ORDER BY 2, 1
```

### Query 6 — Tier 3: Paid Search R$/TP by city (weekly)

Numerator = Demand-committee media cost. Denominator = Prospects from Query 5. Join on `dt_week_start` + `city_group`.

```sql
WITH weekly_cost AS (
    SELECT
        date_trunc('week', dd.date) AS dt_week_start,
        COALESCE(dr.city_group, dsr.city_group) AS city_group,
        SUM(fmpm.total_cost * COALESCE(dsr.share, 1)) AS cost_brl
    FROM dw_growth.fact_media_platform_metrics AS fmpm
    INNER JOIN dw_public.dim_date AS dd
        ON dd.date = fmpm.dt_cost
    LEFT JOIN dw_growth.dim_media_setup AS dms
        ON fmpm.naming_convention_sufix = dms.naming_convention_sufix
    LEFT JOIN dw_public.dim_region AS dr
        ON fmpm.sk_region = dr.sk_region
    LEFT JOIN dw_growth.dim_sharing_rules AS dsr
        ON dsr.bk_sharing_rules = fmpm.bk_sharing_rules
    WHERE LOWER(dms.funnel_side) = 'demand'
      AND fmpm.country_code = 'BR'
      AND dd.date >= DATE '2026-05-01'
      AND dd.date < DATE '2026-07-14'
      AND LOWER(dms.campaign_business_context) = 'rent'
      AND dms.medium IN ('Performance Max', 'SEM non-branded', 'Web Display')
      AND COALESCE(dr.city_group, dsr.city_group) IN ('Porto Alegre', 'Belo Horizonte', 'Rio de Janeiro', 'RMSP')
      AND dms.campaign_strategy_intent <> 'Brand Awareness'
    GROUP BY 1, 2
),
weekly_prospects AS (
    SELECT
        gdp.dt_week_start,
        gdp.city_group,
        SUM(gdp.new_prospects + gdp.recovered_prospects) AS prospects
    FROM metric_growth.growth_demand_performance_weekly AS gdp
    WHERE gdp.country_code = 'BR'
      AND LOWER(gdp.business_context) = 'rent'
      AND gdp.medium IN ('SEM non-branded', 'Performance Max', 'Web Display')
      AND gdp.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Rio de Janeiro', 'RMSP')
      AND gdp.dt_week_start >= DATE '2026-05-01'
      AND gdp.dt_week_start < DATE '2026-07-14'
    GROUP BY 1, 2
)
SELECT
    wc.city_group,
    wc.dt_week_start,
    ROUND(wc.cost_brl, 2) AS cost_brl,
    wp.prospects,
    ROUND(wc.cost_brl / CAST(wp.prospects AS DOUBLE), 2) AS cost_per_tp_brl
FROM weekly_cost AS wc
INNER JOIN weekly_prospects AS wp
    ON wc.dt_week_start = wp.dt_week_start
   AND wc.city_group = wp.city_group
ORDER BY 2, 1
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
