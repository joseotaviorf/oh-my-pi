# ROAS / ECM Credit Impact

## Overview

Analytical frame for measuring whether a new **eCM / ELTV** model — used by the ROAS API to send conversion values to paid media — improves **credit quality** of acquired Tenant Prospects (TPs) without hurting volume.

**Production flow:** each **Visit Booked (VB)** or **Offer Submitted (OS)** triggers the **ROAS API**, which calls **EMLIO** (`id_service = 'eltv'`). EMLIO persists logs in `datalake_emlio_clean.emlio_logs`; the enrich table is `datalake_expected_contribution_margin.expected_contribution_margin` (`ecm`).

The new version of the model now also incorporates "Early Credit" features as input—a product offered to customers allowing them to undergo a preliminary credit assessment (which would otherwise take place later) to gauge their eligibility for the property.

Phase 1: only **Porto Alegre** receives `ecm_version = 'v3'` after cutover on **July 1, 2026**; comparable control cities stay on `v2` (**Belo Horizonte**, **Campinas**). Funnel stages: [`fr_transact.md`](fr_transact.md).

## Glossary and Synonyms

- **ROAS API** → invoked on each VB/OS; calls EMLIO; forwards `estimated_contribution_margin` to ad platforms
- **eCM / ELTV** → model-projected margin per inference; column `estimated_contribution_margin` on `ecm`
- **eCM_without_losses** → back-cast of reported eCM **adding back the v3 default-loss term** the model subtracts; v3 + post-cutover only — see [Appendix — eCM without losses](#appendix--ecm-without-losses)
- **ecm_version** → model config tag per inference: `v3` = new credit-aware model (POA post-cutover); `v2` = prior config. Confirm with cutover date — do not use as sole time proxy
- **Cidade tratamento** → **Porto Alegre** (phase 1); receives `v3` after rollout
- **Cidade comparável** → control city for **all tiers**, same pre/post windows as POA. Phase 1 controls: **Belo Horizonte**, **Campinas** (both remain on `v2`)
- **Early credit**, **crédito antecipado** → pre-offer screening; inputs in `ecm.request`, fallback `ecm.features` when request fields are null
- **Final credit** → post-OA proposal screening; `credit_analysis` + `fact_proposal_credit_flows`
- **Mix de crédito** → always state **which funnel**: Early Credit (Tier 1) vs Final Evaluation (Tier 2); use **`risk_category`** (macro bucket), not `risk_category_canon`
- **risk_category** → macro Sorting Hat credit risk score bucket (A, B, C, …); **this project's mix metric**.
- **risk_category_canon** → granular bucket (A1, A2, A3, …); finer policy label — **out of scope** for this ROAS read unless explicitly requested
- **Guarantee mix** → % share by `guarantee_offered` value (Final Tier 2); Early Tier 1 uses `result` in `ecm.request` / `ecm.features`
- **TP** → tenant prospect (`id_user` / `sk_client`) — ROAS API trigger at VB/OS; for **Tier 3 Growth reads**, TP is the same entity as **Prospect** (VB = visit booked, OS = offer sent)
- **ToF** (Top of Funnel) → user reaching Search, Listing, or Schedule page; `tof_users` in `growth_demand_performance_*`
- **Prospect** (Growth) → user who schedules a visit or submits an offer; `new_prospects + recovered_prospects` — see [`seo.md`](seo.md)
- **Paid Search** (Tier 3 channel slice) → `medium IN ('SEM non-branded', 'Performance Max', 'Web Display')` in `growth_demand_performance_*`
- **ToF2Prospect** → `SUM(new_prospects + recovered_prospects) / SUM(tof_users)` — use `tof_users`, not `tof_events`
- **ES2EP / OA2ES / OA2CA / OA2CS** → cohort conversions; see [Conversion metrics (Tier 2)](#conversion-metrics-tier-2).

## Metric tiers

| Tier | Question | Metrics |
|------|----------|---------|
| **1 — Model** | What does the model change after rollout? | **Output:** sum/mean `estimated_contribution_margin`, call volume. **Early Credit inputs:** % by request `risk_category`; % by `result` |
| **2 — Credit** | Did acquired TPs pass credit better? | **ES2EP** (primary); **OA2ES**, **OA2CA**, **OA2CS** (secondary); final **`risk_category`** mix; **`guarantee_offered`** share mix |
| **3 — Growth** | Did paid top-of-funnel acquisition break? | **Prospects** volume; **ToF2Prospect** rate; **R$/TP** (cost per prospect) — Paid Search slice only |

Comparison strategy:

1) For each eligible city (in version v3), compare the before and after.
2) Eligible cities (v3) vs. comparable cities (v2).

Comparable cities (phase 1): **Belo Horizonte** and **Campinas** — same pre/post windows as POA. Document this list and cutover date (`2026-07-01`) in every query.

**Geographic slice (critical):** v3 rollout is at **city** level (e.g. Porto Alegre proper), not the full **`city_group`** (which includes RM satellites like Canoas, São Leopoldo, …). For **Tier 1 eCM**, always filter `dw_public.dim_region.city_name` via `ecm.id_house → house.id_region` — **not** `city_group`, and **not** `features.city` (incomplete on many rows).

### Conversion metrics (Tier 2)

From `metric_rent.cohort_conversions_volumes` (`rent_cohort`) — **already latest snapshot** (ETL filters today's partition); filter `country_code = 'BR'`, `rental_administrator = 'QUINTOANDAR'`. Reading `dw_rent_snapshot.rent_cohort_conversions_snapshot` directly requires the latest `year`/`month`/`day` filter (see Critical rules).

| Metric | Meaning | Role |
|--------|---------|------|
| **ES2EP** | Evaluation started → positive screening | **Primary** — fastest credit-policy read; most sensitive to score/risk features the model optimizes for |
| **OA2ES** | Offer approved → evaluation started | **Secondary** — share of OAs that enter credit evaluation; upstream of ES2EP on the OA cohort |
| **OA2CA** | Offer approved → credit approved | **Secondary** — credit approval after owner acceptance |
| **OA2CS** | Offer approved → contract signed | **Secondary** — end-to-end outcome from OA; longer maturation than ES2EP / OA2CA |

**rent_cohort columns:**

| Metric | Numerator | Denominator |
|--------|-----------|-------------|
| ES2EP | `es_converted_ep` | `es_converted_ep + es_unconverted` |
| OA2ES | `oa_converted_es` | `oa_converted_es + oa_unconverted` |
| OA2CA | `oa_converted_ca` | `oa_converted_ca + oa_unconverted` |
| OA2CS | `oa_converted_cs` | `oa_converted_cs + oa_unconverted` |

**Rate:** `SUM(converted) / (SUM(converted) + SUM(unconverted))` on the base cohort month (`dt_event` = date of the **denominator stage event** — ES date for ES2EP; OA date for OA2ES / OA2CA / OA2CS). Do **not** use coincident monthly ratios from [`fr_transact.md`](fr_transact.md) Query 8, and do **not** use OA cohort date or `oa_converted_es` as the ES2EP denominator (that pattern matches some Fintech dashboards but is not canonical ES2EP).

### Credit mix definitions

**Tier 1 — Early Credit (model inputs at VB/OS):**
- Read **`risk_category`** (macro) and guarantee **`result`** from `ecm.request` first.
- **Fallback:** when either field is null, read the same keys from `ecm.features` (`risk_category`, `result`).
- Share = `% of eCM API requests` (`COUNT(*)` on `expected_contribution_margin`, `id_service = 'eltv'`) per bucket, by **period** (pre/post cutover) and **`dim_region.city_name`** (via house join). **Denominator is always all requests** in the window — including rows without Early Credit fields.
- When **`risk_category`** is null in both `request` and `features`, bucket as **`s/early_credit`** for full-mix tables; **bar charts may omit this bucket** and show A–E as % of total, with the omitted share noted in the chart title (~80% in POA early monitoring).
- **Guarantee `result` mix:** same denominator rule — FREE / PRO_GUARANTOR / REJECTED as % of **all** requests, not % among rows with `result` filled.
- **Early Credit logging start (POA):** fields first appear in `ecm.features` on **`2026-06-12`** (~20% of daily requests); before that date there is no Early Credit signal. For **mix and eCM-by-risk_category** reads, use **pre = 2026-06-12 through 2026-06-30**, not full June. From **`2026-07-01`** (v3 cutover) the same fields move to `ecm.request`.

**Tier 2 — Final credit (proposal path):**
- % proposals by **`risk_category`** (macro) — first screening per `id_proposal` (`ROW_NUMBER` on `ca.ts_created`).
- % proposals by **`guarantee_offered`** — full share mix, not just FREE vs paid. Report each value separately. Source: `pcf.guarantee_offered` where `is_user_version = TRUE` (or first `ca.guarantee_offered` per proposal).

Shift toward lower-risk buckets **without** ES2EP drop or Paid Search prospect / ToF2Prospect collapse = leading signal the ROAS change worked.

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

**Geography:** `city_group` in these tables (not `city_name`). Filter treatment + controls: **Porto Alegre**, **Belo Horizonte**, **Campinas**. Set `country_code = 'BR'`.

**Comparison:** pre/post around cutover (`2026-07-01`) on the same Paid Search slice; compare POA delta vs control cities. Rising **R$/TP** with flat Prospects and ToF2Prospect = efficiency deterioration; stable **R$/TP** with credit-mix improvement = healthier acquisition.

### Appendix — eCM without losses

**Question:** how much of the reported eCM move is driven by the new **default-loss** component in v3 (`estimated_default_probability`), vs. other model changes (Early Credit, conversion, duration, etc.)?

**What changed in v3 (context):** v3 touches more than default losses — **`estimated_conversion_probability` also shifts** with the new model. That component is **not** back-cast here: isolating its contribution would require a separate decomposition we do not have in logs. This appendix **only reverses the default-loss charge**, which has an explicit, auditable formula.

**Definition (per inference, v3 post-cutover only):**

v3 **subtracts** a default-loss charge inside `estimated_contribution_margin`. To **reverse** that component and see what eCM would be without it:

```
eCM_without_losses =
    estimated_contribution_margin
    + (estimated_conversion_probability * estimated_default_probability * rent * 4)
```

| Input | Source |
|-------|--------|
| `estimated_contribution_margin` | `ecm` column (reported eCM sent to ad platforms) |
| `estimated_conversion_probability` | `ecm` column — **v3 value**; used only to size the loss term, not reversed |
| `estimated_default_probability` | `ecm` column — populated on **v3** inferences only |
| `rent` | `CAST(json_extract_scalar(ecm.features, '$.rent') AS DOUBLE)` |

**Scope:** apply the adjustment **only** when `ecm_version = 'v3'` **and** `ts_event >= cutover` (`2026-07-01`). Before rollout (v2 / pre-cutover), `eCM_without_losses = estimated_contribution_margin` — there is no default-probability loss term.

**Aggregation:** `AVG(eCM_without_losses)` by `city_name` and time window. Compare **reported** vs **without losses** on **Porto Alegre** to quantify how much v3 default pricing depresses the headline number.

**Implementation notes:**
- Pre-cutover or non-v3 rows: leave `estimated_contribution_margin` unchanged.
- `estimated_conversion_probability` in the formula is the **post-v3** value — it scales the loss term but is **not** adjusted to a v2 counterfactual.
- The factor **`4`** is the model's rent multiplier for the default-loss charge (per product spec for v3).
- Remaining v3 vs v2 gap (conversion, duration, Early Credit features, etc.) stays in the residual.
- This is a **diagnostic** metric (appendix), not a replacement for Tier 1 reported eCM.

## Tables

| Need | Table |
|------|-------|
| ROAS inference logs | `datalake_expected_contribution_margin.expected_contribution_margin` (`ecm`) — `id_service = 'eltv'` |
| Cohort conversions (ES2EP, OA2ES, OA2CA, OA2CS) | `metric_rent.cohort_conversions_volumes` (`rent_cohort`) |
| Final credit on proposal | `datalake_credit_analysis.credit_analysis` (`ca`) |
| Proposal guarantee + funnel | `dw_credit.fact_proposal_credit_flows` (`pcf`) — `is_user_version = TRUE` |
| City slice on ECM | `ecm.id_house` → `datalake_ebdb_clean.house` → `dw_public.dim_region` — filter **`dr.city_name`** (not `city_group`; not `features.city`) |
| Growth ToF / Prospects (Tier 3) | `metric_growth.growth_demand_performance_monthly` (or `_weekly` / `_daily`) — filter `medium` for Paid Search |
| Paid media cost (Tier 3 R$/TP) | `dw_growth.fact_media_platform_metrics` + `dw_growth.dim_media_setup` + `dw_public.dim_region` + `dw_growth.dim_sharing_rules` (optional cost allocation) |
| Rent-flow join hub | `dw_rent.fact_rent_flows` (`frf`) |

**Critical rules:**
- **Tier 1:** slice **`dim_region.city_name`** + **cutover date** (pre/post); include comparable control cities in the same windows. Do **not** use `city_group` for eCM — it pools RM satellites still on v2 after POA city rollout.
- **Tier 2+:** `rent_cohort` / snapshot expose `city_group` only today; prefer rebuilding from `dw_rent.fact_rent_cohort_conversions` + `dim_region.city_name` when city-level reads are required (same rule as Tier 1).
- **Tier 3:** slice **`medium`** to Paid Search (`SEM non-branded`, `Performance Max`, `Web Display`); default **`business_context = 'rent'`**; use **`tof_users`** for ToF2Prospect denominator — see [`seo.md`](seo.md). **R$/TP:** join cost (`fact_media_platform_metrics`) and Prospects (`growth_demand_performance_*`) on the **same** `city_group` + time grain; align date keys (`dt_cost` vs `dt_week_start` / `dt_month_start`).
- **Tier 1:** `ecm` has full history — before/after on POA is valid; use `ecm_version` to sanity-check model config, not as sole time proxy.
- **`estimated_contribution_margin` is predicted** — not realized revenue.
- **Early vs Final mix:** Tier 1 = `ecm.request` with **`ecm.features` fallback**; Tier 2 = `ca` / `pcf`. Never swap them.
- **Join ECM → rent flow:** `ecm.id_user = frf.sk_client` AND `ecm.id_house = frf.sk_house`.
- **Join ECM → final credit:** `frf.sk_first_proposal` → `ca.id_proposal`.
- **rent_cohort snapshot:** on `dw_rent_snapshot.rent_cohort_conversions_snapshot` only — filter the **latest** `year`/`month`/`day` partition, then slice `dt_event`. **`metric_rent.cohort_conversions_volumes` already applies this in ETL** — no extra snapshot filter.

## Relationships

- **FR Transact** ([`fr_transact.md`](fr_transact.md)) — funnel stages (VB, OS, OA, ES, EP, CA) and event tables.
- **SEO / Growth demand** ([`seo.md`](seo.md)) — ToF, Prospects, `growth_demand_performance_*`, Paid vs organic `medium` taxonomy.
- **Fintech credit** — `pcf.sk_proposal` ↔ `dw_rent.dim_proposal`; funnel drop codes (`OA2ES`, `ES2EP`, …).

## Dos and Don'ts

**Do:**
- **All tiers:** before/after around POA cutover; add **comparable control cities** in the same pre/post windows; document both cutover date and city list.
- Tier 1: track **both** eCM output and Early Credit input mix in POA pre vs post; compare delta vs control cities.
- Use **ES2EP** as headline conversion; **OA2ES**, **OA2CA**, and **OA2CS** as secondary reads on the OA cohort for distinct hypotheses.
- Tier 3: track **Prospects** volume, **ToF2Prospect**, and **R$/TP** on the **Paid Search** `medium` slice alongside credit mix shifts.
- Filter `ecm.id_service = 'eltv'` for FR Rent ROAS.
- Parse `ecm.request` for Early Credit inputs; **fall back to `ecm.features`** when `risk_category` or `result` is null in request.

**Don't:**
- Don't slice Tier 1 eCM by **`city_group`** — v3 rollout is per **`city_name`**; `city_group = 'Porto Alegre'` still includes Canoas, São Leopoldo, etc. on v2 post-cutover.
- Don't slice Tier 1 eCM by **`features.city`** — field is often null pre-v3 and duplicates house geography inconsistently.
- Don't treat `ecm_version` as a global time flag — anchor on **cutover date + `city_name`**.
- Don't use **final-funnel** mix (`ca`, `pcf`) to answer Tier 1 model-input questions.
- Don't use coincident fr_transact monthly ratios for impact reads.
- Don't read higher reported eCM as proven revenue.
- Don't conflate **`risk_category`** (macro: A, B, C) with **`risk_category_canon`** (granular: A1, A2, A3) — this project tracks macro only.
- Don't use **`tof_events`** for ToF2Prospect — denominator is **`tof_users`** only ([`seo.md`](seo.md)).
- Don't mix organic and paid in Tier 3 — always filter the Paid Search `medium` set; SEO branded/non-branded are out of scope for this ROAS read.
- Don't compute **R$/TP** with mismatched geographies — cost uses `city_group` (or sharing-rule fallback); Prospects must use the same `city_group`, not Tier 1 `city_name`.

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

### Query 2 — Tier 2: ES2EP, OA2ES, OA2CA, OA2CS by city (`cohort_conversions_volumes`)

Uses the metric table (latest snapshot baked in). Then slice `dt_event`.

```sql
SELECT
    rent_cohort.city_group,
    rent_cohort.dt_event,
    -- Primary: ES2EP
    SUM(rent_cohort.es_converted_ep) AS es2ep_converted,
    SUM(rent_cohort.es_unconverted) AS es_unconverted,
    ROUND(
        100.0 * SUM(rent_cohort.es_converted_ep)
        / CAST(NULLIF(SUM(rent_cohort.es_converted_ep) + SUM(rent_cohort.es_unconverted), 0) AS DOUBLE),
        2
    ) AS es2ep_rate_pct,
    -- Secondary: OA2ES
    SUM(rent_cohort.oa_converted_es) AS oa2es_converted,
    SUM(rent_cohort.oa_unconverted) AS oa_unconverted,
    ROUND(
        100.0 * SUM(rent_cohort.oa_converted_es)
        / CAST(NULLIF(SUM(rent_cohort.oa_converted_es) + SUM(rent_cohort.oa_unconverted), 0) AS DOUBLE),
        2
    ) AS oa2es_rate_pct,
    -- Secondary: OA2CA
    SUM(rent_cohort.oa_converted_ca) AS oa2ca_converted,
    ROUND(
        100.0 * SUM(rent_cohort.oa_converted_ca)
        / CAST(NULLIF(SUM(rent_cohort.oa_converted_ca) + SUM(rent_cohort.oa_unconverted), 0) AS DOUBLE),
        2
    ) AS oa2ca_rate_pct,
    -- Secondary: OA2CS
    SUM(rent_cohort.oa_converted_cs) AS oa2cs_converted,
    ROUND(
        100.0 * SUM(rent_cohort.oa_converted_cs)
        / CAST(NULLIF(SUM(rent_cohort.oa_converted_cs) + SUM(rent_cohort.oa_unconverted), 0) AS DOUBLE),
        2
    ) AS oa2cs_rate_pct
FROM metric_rent.cohort_conversions_volumes AS rent_cohort
WHERE rent_cohort.country_code = 'BR'
  AND rent_cohort.rental_administrator = 'QUINTOANDAR'
  AND rent_cohort.city_group IN ('Porto Alegre', 'Belo Horizonte', 'Campinas')
  AND rent_cohort.dt_event >= DATE '2026-01-01'
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 3 — Tier 2: final credit mix by risk_category (macro)

```sql
WITH first_screening AS (
    SELECT
        ca.id_proposal,
        ca.risk_category,
        ca.ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY ca.id_proposal
            ORDER BY ca.ts_created ASC
        ) AS rni
    FROM datalake_credit_analysis.credit_analysis AS ca
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

### Query 4 — Tier 2: guarantee mix by `guarantee_offered` (full share)

```sql
WITH first_screening AS (
    SELECT
        ca.id_proposal,
        ca.guarantee_offered,
        ca.ts_created,
        ROW_NUMBER() OVER (
            PARTITION BY ca.id_proposal
            ORDER BY ca.ts_created ASC
        ) AS rni
    FROM datalake_credit_analysis.credit_analysis AS ca
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

### Query 7 — Appendix: eCM without losses (Porto Alegre)

```sql
SELECT
    DATE_TRUNC('month', ecm.ts_event) AS dt_month,
    dr.city_name,
    COUNT(*) AS roas_api_calls,
    ROUND(AVG(ecm.estimated_contribution_margin), 2) AS avg_ecm_reported,
    ROUND(
        AVG(
            CASE
                WHEN ecm.ts_event >= TIMESTAMP '2026-07-01 00:00:00'
                     AND ecm.ecm_version = 'v3'
                     AND ecm.estimated_default_probability IS NOT NULL
                     AND ecm.estimated_default_probability >= 0
                    THEN ecm.estimated_contribution_margin
                        + (
                            ecm.estimated_conversion_probability
                            * ecm.estimated_default_probability
                            * CAST(json_extract_scalar(ecm.features, '$.rent') AS DOUBLE)
                            * 4
                        )
                ELSE ecm.estimated_contribution_margin
            END
        ),
        2
    ) AS avg_ecm_without_losses
FROM datalake_expected_contribution_margin.expected_contribution_margin AS ecm
INNER JOIN datalake_ebdb_clean.house AS h
    ON ecm.id_house = h.id
INNER JOIN dw_public.dim_region AS dr
    ON h.id_region = dr.id
WHERE ecm.id_service = 'eltv'
  AND dr.city_name = 'Porto Alegre'
  AND ecm.ts_event >= TIMESTAMP '2026-04-01 00:00:00'
GROUP BY 1, 2
ORDER BY 1
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
