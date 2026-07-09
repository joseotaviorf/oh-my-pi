# ROAS / ECM Credit Impact

## Overview

Analytical frame for measuring whether a new **eCM / ELTV** model — used by the ROAS API to send conversion values to paid media — improves **credit quality** of acquired Tenant Prospects (TPs) without hurting volume.

**Production flow:** each **Visit Booked (VB)** or **Offer Submitted (OS)** triggers the **ROAS API**, which calls **EMLIO** (`id_service = 'eltv'`). EMLIO persists logs in `datalake_emlio_clean.emlio_logs`; the enrich table is `datalake_expected_contribution_margin.expected_contribution_margin` (`ecm`).

The new version of the model now also incorporates "Early Credit" features as input—a product offered to customers allowing them to undergo a preliminary credit assessment (which would otherwise take place later) to gauge their eligibility for the property.

Phase 1: the **Porto Alegre** receives `ecm_version = 'v3'` after cutover on **July 1, 2026**; comparable control cities stay on `v2` (**Belo Horizonte**, **Campinas**).

## Glossary and Synonyms

- **ROAS API** → invoked on each VB/OS; calls EMLIO; forwards `estimated_contribution_margin` to ad platforms
- **eCM / ELTV** → model-projected margin per inference; column `estimated_contribution_margin` on `ecm`
- **ecm_version** → model config tag per inference: `v3` = new credit-aware model (POA post-cutover); `v2` = prior config. Confirm with cutover date — do not use as sole time proxy
- **Cidade tratamento** → **Porto Alegre** receives `v3` after rollout
- **Cidade comparável** → control city for **all tiers**, same pre/post windows as POA. Phase 1 controls: **Belo Horizonte**, **Campinas** (both remain on `v2`)
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
- **ES2CA / OA2CS / OA2ES / ES2EP / EP2DS / DS2CA / CA2CS** → coincident conversion rates on `pcf`; see [Conversion metrics (Tier 2)](#conversion-metrics-tier-2).

## Metric tiers

| Tier | Question | Metrics |
|------|----------|---------|
| **1 — Model** | What does the model change after rollout? | **Output:** sum/mean `estimated_contribution_margin`, call volume. **Early Credit inputs:** % by request `risk_category`; % by `result` |
| **2 — Credit** | Did Paid Search–acquired TPs pass credit better? | **ES2CA** (primary); **OA2CS** + sub-stages **OA2ES**, **ES2EP**, **EP2DS**, **DS2CA**, **CA2CS** (secondary); final **`risk_category`** mix; **`guarantee_offered`** share mix — **Paid Search slice** (ROAS-impacted audience) |
| **3 — Growth** | Did paid top-of-funnel acquisition break? | **Prospects** volume; **ToF2Prospect** rate; **R$/TP** (cost per prospect) — Paid Search slice only |

Comparison strategy:

1) For each eligible city (in version v3), compare the before and after.
2) Eligible cities (v3) vs. comparable cities (v2).

Comparable cities (phase 1): **Belo Horizonte** and **Campinas** — same pre/post windows as POA. Document this list and cutover date (`2026-07-01`) in every query.

### Conversion metrics (Tier 2)

**Coincident (MIS / executive alignment)** from `dw_credit.fact_proposal_credit_flows` (`pcf`) — same base as C-level credit reports: `is_last_credit_evaluation = TRUE`, `rental_administrator = 'QUINTOANDAR'`, `country_code = 'BR'`. Each rate = volume of the **target stage in the period** ÷ volume of the **base stage in the period**; stages use **each stage's own date** (not cohort-linked). Do **not** use `is_user_version` for Tier 2 — it excludes re-evaluations (Early Credit, Direct Offer) that MIS keeps via `is_last_credit_evaluation`.

| Metric | Meaning | Role |
|--------|---------|------|
| **ES2CA** | Evaluation started → credit approved | **Primary** |
| **OA2CS** | Offer approved → contract signed | **Secondary** — end-to-end from OA |
| **OA2ES** | Offer approved → evaluation started | Sub-stage of OA2CS |
| **ES2EP** | Evaluation started → evaluation positive | Sub-stage of OA2CS |
| **EP2DS** | Evaluation positive → documentation sent | Sub-stage of OA2CS |
| **DS2CA** | Documentation sent → credit approved | Sub-stage of OA2CS |
| **CA2CS** | Credit approved → contract signed | Sub-stage of OA2CS |

**Stage dates and flags (`pcf`):**

| Metric | Numerator (date) | Denominator (date) |
|--------|------------------|---------------------|
| ES2CA | `dt_credit_analysis_approved_date` | `dt_last_credit_evaluation_init` |
| OA2CS | `dt_contract_signed_date` | `dt_offer_approved_date` |
| OA2ES | `dt_last_credit_evaluation_init` | `dt_offer_approved_date` |
| ES2EP | `ep_flag = 1` → `dt_credit_evaluation_approved_date` | `dt_last_credit_evaluation_init` |
| EP2DS | `dt_tenant_first_doc_sent_date` | `ep_flag = 1` → `dt_credit_evaluation_approved_date` |
| DS2CA | `dt_credit_analysis_approved_date` | `dt_tenant_first_doc_sent_date` |
| CA2CS | `dt_contract_signed_date` | `dt_credit_analysis_approved_date` |

**Rate:** `SUM(numerator volume in period) / SUM(denominator volume in period)` grouped by `DATE_TRUNC` grain + `city_group`. Credit **mix** (`risk_category`, `guarantee_offered`) stays on `credit_analysis` / `pcf` (see below).

**Paid Search slice (primary ROAS audience):** ROAS API spend reaches **Paid Search** only — default **all Tier 2 reads** (conversions + final-credit mix) to that channel. `pcf` has no `medium`; attribute each proposal once:

1. `CAST(pcf.sk_offer AS VARCHAR) = CAST(fdpe.sk_offer AS VARCHAR)`
2. `fdpe.business_context = 'rent'` and **`fdpe.event_name = 'OFFER SUBMITTED'`** (1:1 with OA; no `ROW_NUMBER` dedup needed)
3. `fdpe.naming_convention_sufix` → `dim_media_setup.medium`
4. Keep rows where `medium IN ('SEM non-branded', 'Performance Max', 'Web Display')`

`medium` NULL on `OFFER SUBMITTED` is expected — those proposals are **out of scope** for this product (not Paid Search). All-channel totals (no `fdpe` join) match MIS executive reports — use only as a benchmark, not as the ROAS impact read.

### Credit mix definitions

#### Guarantee display labels

Query on raw source values; use these labels in mix charts and stakeholder reads:

| Display | Early Credit (`ecm.request` / `ecm.features` → `result`) | Final credit (`ca` / `pcf` → `guarantee_offered`) |
|---------|-----------------------------------------------------------|---------------------------------------------------|
| **FREE** | `FREE` | `FREE` |
| **PAID** | `PRO_GUARANTOR` | `PRO_GUARANTOR` |
| **CLEAR_NO** | `REJECTED` | `CLEAR_NO` |

Any other raw value (`DEPOSIT`, `STANDALONE`, `THIRD_PARTY_GUARANTEE`, …) — show **explicitly** under its source name; do not fold into PAID or CLEAR_NO.

**Tier 1 — Early Credit (model inputs at VB/OS):**
- Read **`risk_category`** (macro) and guarantee **`result`** from `ecm.request` first.
- **Fallback:** when either field is null, read the same keys from `ecm.features` (`risk_category`, `result`).
- Share = `% of eCM API requests` (`COUNT(*)` on `expected_contribution_margin`, `id_service = 'eltv'`) per bucket, by **period** (pre/post cutover) and **`dim_region.city_name`** (via house join). **Denominator is always all requests** in the window — including rows without Early Credit fields.
- When **`risk_category`** is null in both `request` and `features`, bucket as **`s/early_credit`** for full-mix tables; **bar charts may omit this bucket** and show A–E as % of total, with the omitted share noted in the chart title (~80% in POA early monitoring).
- **Guarantee `result` mix:** same denominator rule — map to **FREE / PAID / CLEAR_NO** per table above; % of **all** requests, not % among rows with `result` filled.
- **Early Credit logging start (POA):** fields first appear in `ecm.features` on **`2026-06-12`** (~20% of daily requests); before that date there is no Early Credit signal. For **mix and eCM-by-risk_category** reads, use **pre = 2026-06-12 through 2026-06-30**, not full June. From **`2026-07-01`** (v3 cutover) the same fields move to `ecm.request`.

**Tier 2 — Final credit (proposal path)** — **Paid Search proposals only** (join pattern above):
- % proposals by **`risk_category`** (macro) — first screening per `id_proposal` (`ROW_NUMBER` on `ca.ts_created`).
- % proposals by **`guarantee_offered`** — map to **FREE / PAID / CLEAR_NO** per table above; report any other raw value explicitly. Source: `pcf.guarantee_offered` on the MIS base (`is_last_credit_evaluation`, `rental_administrator = 'QUINTOANDAR'`) or first `ca.guarantee_offered` per proposal; restrict to Paid Search via `sk_offer` → `fdpe` (`OFFER SUBMITTED`).

Shift toward lower-risk buckets **without** ES2CA drop or Paid Search prospect / ToF2Prospect collapse = leading signal the ROAS change worked.

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

**Comparison:** pre/post around cutover (`2026-07-01`) on the same Paid Search slice; compare POA delta vs control cities. Rising **R$/TP** with flat Prospects and ToF2Prospect = efficiency deterioration; stable **R$/TP** with credit-mix improvement = healthier acquisition.

## Tables

| Need | Table |
|------|-------|
| ROAS inference logs | `datalake_expected_contribution_margin.expected_contribution_margin` (`ecm`) — `id_service = 'eltv'` |
| Final credit mix + coincident conversions | `dw_credit.fact_proposal_credit_flows` (`pcf`) — MIS base: `is_last_credit_evaluation = TRUE`, `rental_administrator = 'QUINTOANDAR'`, `country_code = 'BR'`; geo via `pcf.sk_region` → `dim_region.city_group` |
| Paid Search channel on proposals (Tier 2) | `dw_growth.fact_demand_prospect_events` (`fdpe`) — `event_name = 'OFFER SUBMITTED'`, join on `sk_offer`; `dw_growth.dim_media_setup` (`dms`) on `naming_convention_sufix` → `medium` |
| Final credit screening attributes | `datalake_credit_analysis.credit_analysis` (`ca`) |
| City slice on ECM (Tier 1) | `ecm.id_house` → `datalake_ebdb_clean.house` → `dw_public.dim_region` — filter **`dr.city_name`** |
| Growth ToF / Prospects (Tier 3) | `metric_growth.growth_demand_performance_monthly` (or `_weekly` / `_daily`) — filter `medium` for Paid Search |
| Paid media cost (Tier 3 R$/TP) | `dw_growth.fact_media_platform_metrics` + `dw_growth.dim_media_setup` + `dw_public.dim_region` + `dw_growth.dim_sharing_rules` (optional cost allocation) |

**Critical rules:**
- **DataHub CI:** primary dataset for this product: `datalake_expected_contribution_margin.expected_contribution_margin`. Other tables in this section are routing references owned by sibling entities — do not list them in `datasets`.
- **Tier 1:** filter **`dim_region.city_name`** (`'Porto Alegre'`, `'Belo Horizonte'`, `'Campinas'`) + **cutover date** (pre/post).
- **Tier 2:** MIS base on `pcf` — `is_last_credit_evaluation = TRUE`, `rental_administrator = 'QUINTOANDAR'`, `country_code = 'BR'`; filter **`dim_region.city_group`** via `pcf.sk_region` — same three values; **default Paid Search** via `pcf.sk_offer` → `fdpe` (`OFFER SUBMITTED`) → `dms.medium` (`SEM non-branded`, `Performance Max`, `Web Display`).
- **Tier 3:** filter **`city_group`** in `growth_demand_performance_*` and cost tables — same three values; slice **`medium`** to Paid Search (`SEM non-branded`, `Performance Max`, `Web Display`); default **`business_context = 'rent'`**; use **`tof_users`** for ToF2Prospect denominator — see [`seo.md`](seo.md). **R$/TP:** join cost and Prospects on the **same** `city_group` + time grain.
- **Tier 1:** `ecm` has full history — before/after on POA is valid; use `ecm_version` to sanity-check model config, not as sole time proxy.
- **`estimated_contribution_margin` is predicted** — not realized revenue.
- **Early vs Final mix:** Tier 1 = `ecm.request` with **`ecm.features` fallback**; Tier 2 = `ca` / `pcf`. Never swap them.

## Relationships

- **SEO / Growth demand** ([`seo.md`](seo.md)) — ToF, Prospects, `growth_demand_performance_*`, Paid Search `medium` taxonomy (Tier 3 volume and efficiency).
- **Fintech credit** — `pcf` + `credit_analysis`; coincident ES2CA / OA2CS sub-stages aligned with MIS executive reports (Tier 2). **Paid Search attribution** — `fdpe` + `dim_media_setup` on `sk_offer`.

## Dos and Don'ts

**Do:**
- **All tiers:** before/after around POA cutover; add **comparable control cities** in the same pre/post windows; document both cutover date and city list.
- Tier 1: track **both** eCM output and Early Credit input mix in POA pre vs post; compare delta vs control cities.
- Use **ES2CA** as headline conversion (coincident `pcf`); **OA2CS** and sub-stages **OA2ES**, **ES2EP**, **EP2DS**, **DS2CA**, **CA2CS** as secondary reads — **Paid Search slice** for ROAS impact (Tier 2).
- Tier 3: track **Prospects** volume, **ToF2Prospect**, and **R$/TP** on the **Paid Search** `medium` slice alongside credit mix shifts.
- Filter `ecm.id_service = 'eltv'` for FR Rent ROAS.
- Parse `ecm.request` for Early Credit inputs; **fall back to `ecm.features`** when `risk_category` or `result` is null in request.

**Don't:**
- Don't slice Tier 1 eCM by **`city_group`** or **`features.city`** — use **`city_name`** via the house join.
- Don't slice Tier 2 or Tier 3 by **`city_name`** — use **`city_group`**.
- Don't treat `ecm_version` as a global time flag — anchor on **cutover date + geography key for the tier**.
- Don't use **final-credit** mix (`ca`, `pcf`) to answer Tier 1 model-input questions.
- Don't use **`metric_rent.cohort_conversions_volumes`** or **`fr_transact`** event-funnel tables for Tier 2 conversion rates — this product uses coincident `pcf` (MIS alignment); Prospects volume is Tier 3 via [`seo.md`](seo.md), not rent-flow stage counts.
- Don't filter Tier 2 `pcf` with **`is_user_version`** — MIS executive reports use **`is_last_credit_evaluation`** (broader; includes non-user credit-evaluation versions).
- Don't use **all-channel** Tier 2 reads as the ROAS impact signal — scope conversions and final-credit mix to **Paid Search** (`fdpe` + `medium` filter); all-channel is MIS benchmark only.
- Don't read higher reported eCM as proven revenue.
- Don't conflate **`risk_category`** (macro: A, B, C) with **`risk_category_canon`** (granular: A1, A2, A3) — this project tracks macro only.
- Don't use **`tof_events`** for ToF2Prospect — denominator is **`tof_users`** only ([`seo.md`](seo.md)).
- Don't mix organic and paid in Tier 2 or Tier 3 — always filter the Paid Search `medium` set on credit reads (`fdpe` join) and Growth reads (`growth_demand_performance_*`); SEO branded/non-branded are out of scope for this ROAS read.
- Don't compute **R$/TP** with mismatched geographies — cost and Prospects must share the same `city_group` and time grain.

## Golden Queries

> Trino patterns. Phase 1 cities: treatment **Porto Alegre**; controls **Belo Horizonte**, **Campinas**. Cutover: `2026-07-01` (pre = May–Jun 2026 for Tier 1 eCM averages; post = Jul 1–7 partial in early monitoring).

### Query 1 — Tier 1: eCM output + Early Credit input mix (before/after + comparable cities)

```sql
SELECT
    DATE_TRUNC('week', ecm.ts_event) AS dt_week,
    dr.city_name,
    CASE
        WHEN ecm.ts_event < TIMESTAMP '2026-07-01 00:00:00' THEN 'pre'
        ELSE 'post'
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
  AND dr.city_name IN ('Porto Alegre', 'Belo Horizonte', 'Campinas')
  AND ecm.year = 2026
  AND ecm.month >= 1
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY 1, 2, 3, 7 DESC
```

### Query 2 — Tier 2: ES2CA, OA2CS + sub-stages by city_group — Paid Search (primary ROAS read)

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
      AND dr.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Campinas')
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

### Query 2b — Tier 2: same rates, all-channel (MIS executive benchmark)

Omit `offer_medium` / `fdpe` join — matches MIS national totals. Use for benchmark only, not ROAS impact reads.

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
      AND dr.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Campinas')
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
  AND gdp.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Campinas')
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
      AND COALESCE(dr.city_group, dsr.city_group) IN ('Porto Alegre', 'Belo Horizonte', 'Campinas')
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
      AND gdp.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Campinas')
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
