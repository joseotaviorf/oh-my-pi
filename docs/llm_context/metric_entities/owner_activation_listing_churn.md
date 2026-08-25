# Owner Activation Listing Churn (H2 2026)

## Ownership

**Data Owner:**
- rosi.silva@quintoandar.com.br

**Data Steward:**
- carolina.almeida@quintoandar.com.br

## Overview

**Owner Activation Listing Churn** is the official **cohort churn rate** used in the **[Growth][OwnerActivation] Cockpit** for H2 2026 OKRs (KR2). For each listing in a **publication cohort**, the metric flags whether the listing is in a churn status at the **maturity boundary** of a fixed window (publication + N×7 days), **without** having converted before that boundary.

This is a **point-in-time cohort snapshot**, not a count of status transitions in a calendar month. **Lower is better.**

**Official OKR numbers** (Cockpit aggregation — **distinct listing rate**, not a naive row average):

- **RENT (4w):** churned matured listings / matured listings in cohort
- **SALE (8w):** same pattern at 8 weeks

```sql
-- Pattern for window Nw (OKR: RENT Nw=4w, SALE Nw=8w); key = sk_house_listing in dataset
COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_churn_Nw AND is_matured_Nw)
/ CAST(COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_matured_Nw) AS DOUBLE)
```

Diagnostic charts use the same formula at **1w** (Cockpit label **L2Churn 1w**), **2w**, **3w**, etc.

Aggregate by `week_pub` or `month_pub` (publication date). Shares the same publication cohort and Superset dataset as **Supply Pricing Score** (KR1) — see [`supply_pricing_score.md`](supply_pricing_score.md).

**Applies to For Rent and For Sale (Brazil), 1P and 3P.**

**Not the same as:**

- **Listing unpublishes** — transition volume into `UNPUBLISHED` per calendar period; see House and Listing domain entity
- **Supply Retention (Sale) Churn** — month-over-month stock reconciliation; see [`supply_retention_sale.md`](supply_retention_sale.md)
- **Unpublishing Rate** (credit policy) — credit-monitoring metric; see [`credit_metrics.md`](credit_metrics.md)

## Related Domain Entities

- House and Listing
- Pricing

## Related Metric Entities

- Supply Pricing Score (Owner Activation H2 2026) — sibling KR1 in the same Cockpit dataset

## Catalog

| Metric | Type |
| :---- | :---- |
| Listing Churn (RENT, 4w) | OKR |
| Listing Churn (SALE, 8w) | OKR |

## MBR

- Growth MBR

## Glossary and Synonyms

- **Listing Churn**, **churn rate**, **churn de listing**, **Owner Activation churn** → this metric family
- **L2Churn Nw** (Cockpit) → listing churn rate at the N-week boundary (e.g. **L2Churn 1w**)
- **Churn OKR (RENT)** → `COUNT DISTINCT` churned / `COUNT DISTINCT` matured at **4w**
- **Churn OKR (SALE)** → `COUNT DISTINCT` churned / `COUNT DISTINCT` matured at **8w**
- **is_churn_Nw** → boolean per listing at the N-week boundary after publication
- **reason_churn_Nw** → `status_change_reason` on the status interval active at the boundary (diagnostic)
- **Cohort churn** → churn evaluated at publication cohort maturity, not calendar-month unpublish volume
- **Retention** → not defined here; do not invert churn without an explicit formula

## Scope

**Included:**

- **SALE:** listings with `ts_first_publication` from `2026-01-01` through D-1 (`< CURRENT_DATE`), `price IS NOT NULL` on `dw_sale.dim_listing`
- **RENT:** `dw_rent.dim_house_listing` with `version > 0`, `listing_category_start IN ('First Listing', 'Re-Listing', 'Recovered')`, same publication window
- **1P and 3P** (`is_3p_supply` available for segmentation; Cockpit has no default channel filter)
- Windows **1w–8w** at listing level (`is_churn_1w` … `is_churn_8w`) for diagnostics; OKR headline uses **4w (RENT)** and **8w (SALE)** only

**Excluded:**

- Listings outside the publication date window
- Immature cohorts when reporting OKR headline metrics
- Listings that **converted before** the cohort boundary (signed rent contract or sale agreement before `ts_boundary`)
- Transition-based unpublish counts — use House and Listing unpublish definition instead

## Calculation

**Grain:** one row per listing in the publication cohort — `sk_house_listing` (RENT) or `sk_sale_listing` (SALE).

**Cohort boundaries:** `dt_cohort_Nw = dt_pub + N×7 days`; `ts_boundary = ts_publication + N×7 days`. **Maturity:** `is_matured_Nw = (dt_cohort_Nw < CURRENT_DATE)`.

**Status snapshot:** active status interval at `ts_boundary` from `dw_rent.fact_house_listing_status` (RENT) or `dw_sale.fact_listing_status` (SALE):

```sql
ts_status_start/started <= ts_boundary
AND (ts_status_end/ended > ts_boundary OR ts_status_end/ended IS NULL)
```

### SALE — `is_churn_Nw = TRUE` when

1. At the boundary, `status_history IN ('UNPUBLISHED', 'SUSPENDED', 'EDITING', 'OPTED_OUT')`
2. **Exclude** when `status_history IN ('UNPUBLISHED', 'SUSPENDED')` **and** `status_change_reason = 'OWNER_RENTED_HOUSE'`
3. **Not converted** before boundary: `dt_first_sale_agreement_signed IS NULL OR dt_first_sale_agreement_signed > ts_boundary` (from `dw_sale.dim_listing`)

### RENT — `is_churn_Nw = TRUE` when

1. At the boundary:
   - `status_history IN ('UNPUBLISHED', 'OPTED_OUT')`, **or**
   - `status_history = 'SUSPENDED'` **and** `COALESCE(status_change_reason, '') NOT IN ('ContractDraft', 'RENTED', 'HouseReserved', 'PaidGuarantee', 'Admin')`
2. **Not converted** before boundary: `ts_sig IS NULL OR ts_sig > ts_boundary`, where `ts_sig` = minimum `dw_rent.dim_contract.ts_signature` with `ts_signature > ts_publication` (via `fact_contracts`)

### OKR aggregation

**Canonical Cockpit formula** — ratio of **distinct listings** churned vs **distinct listings** in the matured window (denominator = matured cohort only; immature listings are excluded from both numerator and denominator):

```sql
-- RENT OKR (4w)
COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_churn_4w AND is_matured_4w)
/ CAST(COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_matured_4w) AS DOUBLE)

-- SALE OKR (8w)
COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_churn_8w AND is_matured_8w)
/ CAST(COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_matured_8w) AS DOUBLE)
```

**1w example (diagnostic, Cockpit name):**

```sql
COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_churn_1w AND is_matured_1w)
/ CAST(COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_matured_1w) AS DOUBLE) AS "L2Churn 1w"
```

Result is a **rate** (0–1); Cockpit displays as percent (e.g. 24.0%). Group by `month_pub` or `week_pub` when trending.

**Equivalence note:** If the dataset has **exactly one row per `sk_house_listing`** per aggregation group, this equals `AVG(is_churn_Nw)` over `is_matured_Nw = TRUE`. The Cockpit uses **`COUNT DISTINCT`** so duplicate rows per listing do not distort the rate — prefer the `FILTER` formula to match Superset.

### Canonical Filter

**Publication cohort (both contexts)** — identical to [`supply_pricing_score.md`](supply_pricing_score.md):

```sql
-- SALE
ts_first_publication >= DATE '2026-01-01'
AND ts_first_publication < CURRENT_DATE
AND price IS NOT NULL

-- RENT
version > 0
AND ts_publication >= DATE '2026-01-01'
AND ts_publication < CURRENT_DATE
AND listing_category_start IN ('First Listing', 'Re-Listing', 'Recovered')
```

**OKR headline** — use the **`COUNT DISTINCT` / `FILTER`** ratio above on the correct window (RENT **4w**, SALE **8w**). Do not include immature listings in the denominator.

**Warning:** Counting UNPUBLISHED **transitions** in a calendar month, using immature cohorts in the OKR average, or applying SALE churn rules to RENT (or vice versa) will not match the Cockpit. **EDITING** counts as churn for SALE but is excluded from the default unpublish transition definition in House and Listing.

### Nuances

| Topic | Detail |
| :---- | :---- |
| **Implementation** | Computed inline in the Owner Activation virtual dataset (`krs_h2.sql` — `sale_churn` / `rent_churn` CTEs); not materialized in `sandbox.*` |
| **SALE statuses** | Includes **EDITING** and **OPTED_OUT** in addition to UNPUBLISHED/SUSPENDED |
| **RENT SUSPENDED** | Only churn when reason is **not** operational/contract-related (exclusion list in SQL) |
| **OWNER_RENTED_HOUSE** | Excluded for SALE UNPUBLISHED/SUSPENDED — owner rented the house elsewhere |
| **Conversion guard** | Rent: contract signature after publication; Sale: `dt_first_sale_agreement_signed` |
| **Diagnostic windows** | `is_churn_1w` … `is_churn_3w` available for ad-hoc analysis; not OKR headline |
| **Targets in dataset** | Embedded constants: RENT `target_churn = 0.272`, SALE `target_churn = 0.274` — confirm against planning if comparing to official OKR target |

**Validation reference (March 2026, `month_pub = 2026-03`, matured cohorts, 1P+3P):**

| Context | OKR window | Cockpit value |
|---------|------------|---------------|
| RENT | L2Churn **4w** (`COUNT DISTINCT` / matured) | **24.0%** |
| SALE | L2Churn **8w** (`COUNT DISTINCT` / matured) | **25.2%** |

## Dos and Don'ts

**Do:**

- Use the **`COUNT(DISTINCT sk_house_listing) FILTER (...)`** ratio for Cockpit parity (RENT **4w**, SALE **8w** OKR)
- Use the same pattern for diagnostics (**L2Churn 1w**, 2w, 3w, …)
- Evaluate status at the **cohort boundary** (`ts_publication + N×7 days`), not at arbitrary calendar month-end
- Apply conversion exclusions before labeling churn
- Segment with `is_3p_supply` when the question is 1P vs 3P
- Route **unpublish transition volume** questions to House and Listing **Listing unpublishes**
- Use **`reason_churn_Nw`** for breakdowns by `status_change_reason` at the boundary

**Don't:**

- Don't count UNPUBLISHED **events** per month as this OKR — different grain and filters
- Don't include **EDITING** in unpublish transition metrics and assume parity with SALE churn
- Don't treat all **SUSPENDED** RENT rows as churn — operational suspensions are excluded
- Don't use **`AVG(is_churn_Nw)`** unless you have confirmed **one row per `sk_house_listing`** in the aggregation grain — Cockpit uses **`COUNT DISTINCT`**
- Don't confuse with **Supply Retention** or **credit Unpublishing Rate** metrics
- Don't invert churn to "retention %" without defining the formula explicitly

## Golden Queries

Listing-level churn flags mirror the Owner Activation dataset (`krs_h2.sql`). Below: **official OKR aggregation** by publication month.

### Query 1 — Listing Churn OKR (RENT, monthly)

```sql
WITH windows AS (
    SELECT * FROM (VALUES ('4w', INTERVAL '28' DAY)) AS t(window_label, window_offset)
),
rent_pub_cohort AS (
    SELECT
        sk_house_listing,
        ts_publication,
        CAST(ts_publication AS DATE) AS dt_pub,
        DATE_TRUNC('month', CAST(ts_publication AS DATE)) AS month_pub,
        CAST(ts_publication AS DATE) + INTERVAL '28' DAY AS dt_cohort_4w
    FROM dw_rent.dim_house_listing
    WHERE version > 0
      AND ts_publication >= DATE '2026-01-01'
      AND ts_publication < CURRENT_DATE
      AND listing_category_start IN ('First Listing', 'Re-Listing', 'Recovered')
),
rent_signed AS (
    SELECT
        c.sk_house_listing,
        MIN(CASE WHEN dc.ts_signature > c.ts_publication THEN dc.ts_signature END) AS ts_sig
    FROM rent_pub_cohort AS c
    LEFT JOIN dw_rent.fact_contracts AS fc ON fc.sk_house_listing = c.sk_house_listing
    LEFT JOIN dw_rent.dim_contract AS dc ON dc.sk_contract = fc.sk_contract
    GROUP BY c.sk_house_listing
),
rent_status_cohorts AS (
    SELECT
        c.sk_house_listing,
        c.month_pub,
        c.dt_cohort_4w,
        fls.status_history,
        fls.status_change_reason,
        s.ts_sig,
        c.ts_publication + w.window_offset AS ts_boundary
    FROM rent_pub_cohort AS c
    CROSS JOIN windows AS w
    LEFT JOIN rent_signed AS s ON s.sk_house_listing = c.sk_house_listing
    LEFT JOIN dw_rent.fact_house_listing_status AS fls
        ON fls.sk_house_listing = c.sk_house_listing
       AND fls.country_code = 'BR'
       AND fls.ts_status_start <= c.ts_publication + w.window_offset
       AND (fls.ts_status_end > c.ts_publication + w.window_offset OR fls.ts_status_end IS NULL)
),
rent_churn AS (
    SELECT
        sk_house_listing,
        month_pub,
        dt_cohort_4w,
        MAX(
            (status_history IN ('UNPUBLISHED', 'OPTED_OUT')
                OR (status_history = 'SUSPENDED'
                    AND COALESCE(status_change_reason, '') NOT IN
                        ('ContractDraft', 'RENTED', 'HouseReserved', 'PaidGuarantee', 'Admin')))
            AND (ts_sig IS NULL OR ts_sig > ts_boundary)
        ) AS is_churn_4w
    FROM rent_status_cohorts
    GROUP BY sk_house_listing, month_pub, dt_cohort_4w
),
rent_listing_flags AS (
    SELECT
        sk_house_listing,
        month_pub,
        is_churn_4w,
        dt_cohort_4w < CURRENT_DATE AS is_matured_4w
    FROM rent_churn
)
SELECT
    month_pub,
    COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_churn_4w AND is_matured_4w)
    / CAST(COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_matured_4w) AS DOUBLE) AS listing_churn_okr_rent_4w
FROM rent_listing_flags
GROUP BY month_pub
ORDER BY month_pub
```

### Query 2 — Listing Churn OKR (SALE, monthly)

SALE requires the full status-at-boundary chain from the Cockpit SQL. Reproduce `sale_pub_cohort` → `sale_status_cohorts` → `sale_churn` from `krs_h2.sql`, then aggregate:

```sql
-- After building sale_final (or equivalent) with is_churn_8w and is_matured_8w:
SELECT
    month_pub,
    COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_churn_8w AND is_matured_8w)
    / CAST(COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_matured_8w) AS DOUBLE) AS listing_churn_okr_sale_8w
FROM sale_final
GROUP BY month_pub
ORDER BY month_pub
```

## Superset Golden Assets

- **[Growth][OwnerActivation] Cockpit Dashboard** — Owner Activation KPI cockpit (Pricing Score + Churn). Reference only for navigation. URN: `urn:li:dashboard:(superset,dashboard.4240)`
- **[OwnerActivation] KRs - H2 2026 - SALE & RENT [Growth]** — canonical virtual dataset for listing-level cohort metrics (union SALE + RENT). Churn computed inline in SQL (`is_churn_*`, `reason_churn_*`). URN: `urn:li:dataset:(urn:li:dataPlatform:superset,22993,PROD)`
