# Listing to Well Priced (L2Wp)

## Ownership

**Data Owner:**
- alexandre.gimenez@quintoandar.com.br

**Data Steward:**
- bruna.prates@quintoandar.com.br

## Overview

**Listing to Well Priced (L2Wp)** measures the **share or volume of rent listings classified as well priced** — published price **within the ideal limit** (not overpriced) — in a **publication cohort**.

At its core:

```
well priced listing = price_score flag = 1 on sandbox.listing_scores for the chosen snapshot (Pub or 4W)
```

**L2Wp is a publication-cohort pricing-health rate**, not a demand-funnel conversion (not L2VB/L2R) and not the combined **Quality Pub / Quality 4Ws** score (which adds `easy_entry`).

**Exists exclusively for For Rent (Brazil).** Schema and listing grain → `domain_entities/house_and_listing.md`. **Well priced definition** (p90 rule) → `domain_entities/pricing.md`.

**Data Product:** **supply-quality-score** (DataHub) — `price_score` is the pricing lever; L2Wp is the **price-only** cohort share derived from the same `sandbox.listing_scores` source used in `metric_entities/supply_quality_score.md`.

**Tables:** `sandbox.listing_scores` + `dw_rent.dim_house_listing` (+ `dw_growth.obt_supply` for 1P channel when matching the official dashboard). Optional pre-aggregates: `metric_rent.relisting_well_priced_monthly`, `metric_rent.relisting_well_priced_weekly` (`pct_well_priced`).

## Related Domain Entities

- House and Listing
- Pricing

## Catalog

| Metric | Type |
| :---- | :---- |
| Listing to Well Priced — Pub (L2Wp Pub) | Health Metric |
| Listing to Well Priced — 4W (L2Wp 4W) | Health Metric |
| FL2WP (First Listing → Well Priced) | Health Metric |
| RL2WP (Re-Listing → Well Priced) | Health Metric |
| RC2WP (Recovered → Well Priced) | Health Metric |

## Glossary and Synonyms

- **L2Wp**, **Listing to Well Priced**, **Listing2WellPriced**, **listing → well priced** → **preferred names**
- **Total Listings Well Priced** (DataHub glossary) → **L2Wp Pub** — well-priced share at **publication (D0)**; `price_score_pub`
- **Relisting Well Priced - 4W** (DataHub glossary) → **L2Wp 4W** on **Re-Listing / Recovered** cohorts — `price_score_4w` after **28-day maturation**
- **Well priced volume** → `COUNT(DISTINCT sk_house_listing)` with `price_score_* = 1` — numerator only; state cohort and snapshot (Pub vs 4W)
- **pct_well_priced** → column on `metric_rent.relisting_well_priced_*` pre-aggregates — use when reproducing dashboard cuts without rebuilding from `listing_scores`
- **Quality Pub / Quality 4Ws** → **different metrics** — `(price_score + easy_entry) / listings`; see `metric_entities/supply_quality_score.md`
- **Overpriced / imóvel overpriced** → complement of well priced at the ideal limit — see `domain_entities/pricing.md`
- **NL**, **New Listings**, **novas publicações** → listings **published in a reference period** (cohort). **RENT:** FL + RL + RC (`listing_category_start`). **SALE:** **FL only** (no rent-style versioning)
- **OL**, **Ongoing Listings**, **estoque publicado** → listings **currently PUBLISHED** on a reference day (inventory snapshot) — see `metric_entities/ongoing_listings.md`
- **FL**, **First Listing** → `listing_category_start = 'First Listing'` (**RENT**); SALE first publication — see `metric_entities/first_listings_1p.md`
- **RL**, **Re-Listing** → `listing_category_start = 'Re-Listing'` (**RENT only**)
- **RC**, **Recovered** → `listing_category_start = 'Recovered'` (**RENT only**)
- **FL2WP**, **RL2WP**, **RC2WP** → **L2Wp Pub** (or 4W when specified) scoped to one **`listing_category_start`** — same formula as L2Wp, filter the category
- **L2R by pricing tier**, **L2CCV by pricing tier**, **L2VB by pricing tier**, **conversão well priced vs overpriced** → cross-metric slice — see **Conversion by pricing tier (L2R / L2VB / L2CCV)** below

## Scope

**Included:** rent listing versions (`sk_house_listing`) with a publication anchor on `sandbox.listing_scores` (`listing_start_dt` / `listing_start_mth`).

**RENT only** — no SALE L2Wp. Do not search L2VB-style SALE equivalents.

**Official dashboard baseline (Supply Quality):**

- `country_code = 'BR'`
- `listing_category_start = 'First Listing'` for **Total Listings Well Priced** / corporate **Quality Pub** cuts
- `listing_category_start IN ('Re-Listing', 'Recovered')` for **Relisting Well Priced - 4W**
- **1P** channel (`obt_supply` attribution — same `base_supply` CASE as `supply_quality_score.md`)
- `date(listing_start_dt) >= date('2025-08-01')` for current-era dashboards
- **August Bug** exclusion for 4W: `NOT (EXTRACT(MONTH FROM listing_start_dt) = 8 AND hdi4.rent IS NULL)`

**4W specific:** `time_completed_4w = TRUE` — exclude immature cohorts (same rule as Quality 4Ws).

**Excluded (unless requested):** 3P / Rede supply in the official baseline; listings without calculator coverage that yield `price_score = 0` or NULL handling per `listing_scores` logic.

**Cohort grain:** `sk_house_listing` (one row per rent listing version).

**Not the same as:**

- **Quality Pub / Quality 4Ws** — combined pricing + easy-entry score
- **L2R** — signed contract conversion
- **Binary overpriced flag** from ad-hoc `dim_pricing` + `price_prediction.p90` — related concept; **official L2Wp uses `price_score` on `listing_scores`**

---

## Calculation

Every **rate** view is the same ratio, evaluated per **publication** cohort:

```
L2Wp (cohort) = COUNT(DISTINCT listings with price_score_* = 1)
              / COUNT(DISTINCT listings in cohort)
```

Equivalent when `price_score_*` is 0/1 per listing:

```
L2Wp (cohort) = SUM(price_score_*) / COUNT(DISTINCT sk_house_listing)
```

**Volume (numerator only):**

```
well_priced_listings = COUNT(DISTINCT sk_house_listing WHERE price_score_* = 1)
```

### Answering “O que significa a métrica L2Wp?”

1. **L2Wp = Listing to Well Priced** — share (or count) of listings **well priced** vs total in a **publication cohort**.
2. **RENT / BR only** — not part of the L2VB/L2CCV demand-funnel family.
3. **Pick the snapshot:**
   - **Pub (D0)** → `price_score_pub` — “nasce bem precificado?”
   - **4W (28 days)** → `price_score_4w` + `time_completed_4w = TRUE` — “permanece bem precificado após 4 semanas?”
4. **Pick the listing category** when the question names it:
   - **Total Listings Well Priced** → typically **First Listing**
   - **Relisting Well Priced - 4W** → **Re-Listing** / **Recovered**
5. **Relates to supply-quality-score** — `price_score` lever; for combined pricing + entry use **Quality Pub / Quality 4Ws**.

### Answering “Share well priced e overpriced — quebrar por NL e OL”

**NL and OL are different grains — run both when the question asks for both.**

| Slice | Meaning | Grain | RENT category breakdown | SALE |
|-------|---------|-------|-------------------------|------|
| **OL** | Current **published stock** | Snapshot (today or chosen day) | **FL / RL / RC** via `listing_category_start` on live `PUBLISHED` rows | **FL only** — no RL/RC |
| **NL** | **New publications** in a period | Publication cohort (month/week) | **FL / RL / RC** via `listing_category_start` | **FL only** |

**RENT category map (NL and OL):**

| Code | `listing_category_start` | L2Wp variant (Pub) |
|------|--------------------------|-------------------|
| **FL** | `'First Listing'` | **FL2WP** |
| **RL** | `'Re-Listing'` | **RL2WP** |
| **RC** | `'Recovered'` | **RC2WP** |
| **NL (total)** | all three | pool or sum of FL + RL + RC |

**Which source for well priced / overpriced?**

| Slice | Preferred source | Well priced | Overpriced |
|-------|------------------|-------------|------------|
| **NL** (official L2Wp / dashboard) | `sandbox.listing_scores` | `price_score_pub = 1` (Pub) or `price_score_4w = 1` (4W) | `price_score_* = 0` or `1 - price_score_*` |
| **OL** (inventory snapshot) | `dw_listing.dim_pricing` + `price_prediction` | `price <= p90` (RENT) / `price <= p70` (SALE) | `price > p90` / `price > p70` — see `domain_entities/pricing.md` |

Do **not** use the OL snapshot SQL for **NL cohort** questions (or vice versa). State the period for **NL** and the reference day for **OL**.

Report **`n_listings`**, **`well_priced`**, **`overpriced`**, and **`share`** per segment. When calculator coverage is missing, exclude or label **`unknown`** — do not silently bucket as well priced.

### Views by time grain

| View | Cohort axis | Price snapshot | Official glossary name |
|------|-------------|----------------|------------------------|
| **Monthly rate (Pub)** | `listing_start_mth` | `price_score_pub` | **Total Listings Well Priced** |
| **Monthly rate (4W)** | `listing_start_mth` | `price_score_4w` + maturation | **Relisting Well Priced - 4W** (when relisting cohort) |
| **Weekly rate** | `listing_start_week` | same `price_score_*` column | Same formula, different bucket |

Report **`total_listings`**, **`well_priced_listings`**, and **`l2wp_rate`** together.

### Canonical filter (Pub — First Listing, 1P, BR)

Reuse the `base_supply` CTE from `metric_entities/supply_quality_score.md`, then:

```sql
dhl.listing_category_start = 'First Listing'
AND date(qs.listing_start_dt) >= date('2025-08-01')
AND base_supply.is_3p_fr = '1P'
```

### Canonical filter (4W — Relisting, 1P, BR)

```sql
dhl.listing_category_start IN ('Re-Listing', 'Recovered')
AND qs.time_completed_4w = TRUE
AND date(qs.listing_start_dt) >= date('2025-08-01')
AND base_supply.is_3p_fr = '1P'
AND NOT (EXTRACT(MONTH FROM qs.listing_start_dt) = 8 AND hdi4.rent IS NULL)
```

### Pre-aggregated shortcut

When the question targets **dashboard parity** for relisting 4W cuts:

```sql
SELECT cohort_period, pct_well_priced
FROM metric_rent.relisting_well_priced_monthly
ORDER BY cohort_period DESC
```

Confirm filters and grain in the table metadata before treating as official — rebuild from `listing_scores` when dimensions (city, 1P rule) differ.

## Conversion by pricing tier (L2R / L2VB / L2CCV)

**Question patterns:**

- “Qual é o **L2R** e **L2CCV** de imóveis **well priced vs overpriced**?”
- “Qual é o **L2VB** de **well priced vs overpriced**?”

This is a **cross-metric slice**: official **demand-funnel or closing conversion rate** **grouped by pricing tier at publication** — not a new named metric in DataHub.

### Answering the question

1. **Confirm RENT vs SALE** — **L2VB exists in both contexts** (unlike L2TP). If unspecified, **report both** in separate tables.
2. **Classify pricing at publication (D0)** — same moment as **L2Wp Pub**. **Never** use `dim_pricing.is_last_price = TRUE` for a publication-cohort conversion cross — that is **current** price (OL grain), not publication price.
3. **Pick the conversion window** — state explicitly:
   - **L2VB default:** **1W / 2W / 4W** from publication — `metric_entities/listing_demand_funnel_conversions.md`
   - **L2R default:** monthly publication cohort, **ever signed** (no window) — `metric_entities/listing_to_rental.md`
   - **L2R optional:** 4W / 8W via `days_listing_to_contract_signed`
   - **L2CCV default:** **8W / 12W / M0+M1** from `ts_first_publication` — `listing_demand_funnel_conversions.md`
4. Report **`total_listings`**, **`conversions`**, and **rate** per `pricing_status` (`well_priced` / `overpriced`).

| Context | Conversion metric | Cohort anchor | Pricing tier at publication | Conversion signal |
|---------|-------------------|---------------|----------------------------|-------------------|
| **RENT** | **L2VB** | `dhl.ts_publication`, `sk_house_listing` | **`price_score_pub`** (preferred) | `fact_listing_rent_flows` — `sk_booking_created_date > 0` within window |
| **RENT** | **L2R** | same | **`price_score_pub`** | `fact_house_listings` on `sk_house_listing` |
| **SALE** | **L2VB** | `dl.ts_first_publication`, `sk_sale_listing` | **Publication price vs `p70`** | `fact_visits` — `ts_booking_created` within window on `sk_house` |
| **SALE** | **L2CCV** | same | **Publication price vs `p70`** | `dim_sale_agreement` via `fact_offers` on `sk_house` |

**Same pricing-tier rules as L2R / L2CCV** — see table below. **L2VC / L2OS** follow the **same cross pattern** as L2VB (swap the demand flag); only document L2VB unless the question names another funnel step.

**RENT pricing tier from `listing_scores`:**

| `price_score_pub` | Tier |
|-------------------|------|
| `1` | **well_priced** |
| `0` | **overpriced** |
| NULL / missing row | **unknown** — exclude or label separately; do not bucket silently |

**SALE pricing tier:** compare **price active at first publication** to **`price_prediction.p70`** (or legacy `predicted_price_70` on `dim_listing` only when prediction join is unavailable — label as fallback).

**Not the same as:**

- **L2Wp** alone — pricing share without conversion
- **OL snapshot** well/over share — current stock, not cohort conversion
- **Quality Pub** — includes `easy_entry`, not conversion

### Common mistake (do not copy)

```sql
-- WRONG for publication-cohort L2R: is_last_price = current price, not D0
FROM dw_listing.dim_pricing AS dp
WHERE dp.is_last_price = TRUE
```

## Dos and Don'ts

**Do:**

- Route **L2Wp** questions to this file — explain **Pub vs 4W** and **First Listing vs Relisting** before SQL
- Use `sandbox.listing_scores` + `price_score_pub` / `price_score_4w` for official parity with **supply-quality-score**
- Apply **`time_completed_4w = TRUE`** on all **4W** cuts
- Link **well priced** semantics to `domain_entities/pricing.md` (ideal limit / p90 rule)
- Report **volume** and **rate** explicitly when the question says “volume” vs “share” / “%”
- When asked for **NL and OL**, produce **two tables** (or two sections) — snapshot OL + cohort NL
- Break **RENT** NL/OL by **FL / RL / RC** (`listing_category_start`); **SALE** NL is **FL only**
- For **L2R / L2VB / L2CCV × pricing tier**, classify at **publication** — `price_score_pub` (RENT) or pub price vs **p70** (SALE)

**Don't:**

- Treat **NL** and **OL** as mystery acronyms — **NL = New Listings**, **OL = Ongoing Listings**
- Use **OL snapshot** (`dim_pricing` + `price_prediction`) for **NL cohort** L2Wp — use **`listing_scores`**
- Expect **RL / RC** on **SALE** — rent versioning only

- Invent a definition when DataHub glossary terms exist — map **Total Listings Well Priced** → L2Wp Pub, **Relisting Well Priced - 4W** → L2Wp 4W relisting
- Confuse **L2Wp** with **Quality Pub / Quality 4Ws** (those add `easy_entry`)
- Apply **L2Wp** to **SALE** or mix with **L2VB / L2R** funnel metrics
- Include immature 4W cohorts without labeling them incomplete
- Use `dim_house_listing.status` snapshot alone — L2Wp comes from **`listing_scores`**
- Use **`is_last_price`** pricing for **publication-cohort L2R / L2VB / L2CCV** crosses — wrong grain
- Default **L2VB** to **RENT only** when SALE is not excluded — run **both** contexts

## Golden Queries

### Query 1 — L2Wp Pub monthly (First Listing, 1P, BR)

Well-priced **share at publication** — aligns with **Total Listings Well Priced**.

```sql
WITH base_supply AS (
    SELECT DISTINCT
        obt.sk_house,
        CASE
            WHEN upper(obt.planning_operation) = 'REDE' THEN '3P REDE'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.nm_business_context = 'RENT'
                 AND obt.sk_user_conversion IN (8919771, 11299701, 6001450) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.nm_business_context = 'RENT'
                 AND lower(obt.nm_agent) IN ('ciq_pj', '3p_fr') THEN '3P Operations'
            ELSE '1P'
        END AS is_3p_fr
    FROM dw_growth.obt_supply AS obt
    WHERE obt.nm_business_context = 'RENT'
      AND obt.country_code = 'BR'
      AND obt.cd_funnel_step = 'first_listing'
      AND obt.date < current_date
)
SELECT
    CAST(qs.listing_start_mth AS DATE) AS cohort_period,
    COUNT(DISTINCT qs.sk_house_listing) AS total_listings,
    COUNT(DISTINCT CASE WHEN qs.price_score_pub = 1 THEN qs.sk_house_listing END) AS well_priced_listings,
    1.000 * SUM(qs.price_score_pub)
        / NULLIF(COUNT(DISTINCT qs.sk_house_listing), 0) AS l2wp_pub_rate
FROM sandbox.listing_scores AS qs
INNER JOIN dw_rent.dim_house_listing AS dhl
    ON qs.sk_house_listing = dhl.sk_house_listing
INNER JOIN base_supply AS bs
    ON dhl.id_house = bs.sk_house
WHERE date(qs.listing_start_dt) >= date('2025-08-01')
  AND dhl.listing_category_start = 'First Listing'
  AND bs.is_3p_fr = '1P'
GROUP BY 1
ORDER BY 1 DESC
```

### Query 2 — L2Wp 4W monthly (Relisting, 1P, BR)

Well-priced **share after 28 days** — aligns with **Relisting Well Priced - 4W**.

```sql
WITH base_supply_ranked AS (
    SELECT
        obt.sk_house,
        CASE
            WHEN upper(obt.planning_operation) = 'REDE' THEN '3P REDE'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.nm_business_context = 'RENT'
                 AND obt.sk_user_conversion IN (8919771, 11299701, 6001450) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.nm_business_context = 'RENT'
                 AND lower(obt.nm_agent) IN ('ciq_pj', '3p_fr') THEN '3P Operations'
            ELSE '1P'
        END AS is_3p_fr,
        ROW_NUMBER() OVER (PARTITION BY obt.sk_house ORDER BY obt.date DESC) AS rn
    FROM dw_growth.obt_supply AS obt
    WHERE obt.nm_business_context = 'RENT'
      AND obt.country_code = 'BR'
      AND obt.cd_funnel_step = 'first_listing'
      AND obt.date >= DATE '2025-06-01'
),
base_supply AS (
    SELECT sk_house, is_3p_fr
    FROM base_supply_ranked
    WHERE rn = 1
)
SELECT
    CAST(qs.listing_start_mth AS DATE) AS cohort_period,
    COUNT(DISTINCT qs.sk_house_listing) AS total_listings,
    COUNT(DISTINCT CASE WHEN qs.price_score_4w = 1 THEN qs.sk_house_listing END) AS well_priced_listings,
    1.000 * SUM(qs.price_score_4w)
        / NULLIF(COUNT(DISTINCT qs.sk_house_listing), 0) AS l2wp_4w_rate
FROM sandbox.listing_scores AS qs
INNER JOIN dw_rent.dim_house_listing AS dhl
    ON qs.sk_house_listing = dhl.sk_house_listing
INNER JOIN base_supply AS bs
    ON dhl.id_house = bs.sk_house
LEFT JOIN datalake_rental_historical_follow_up.house_listings_daily_info AS hdi4
    ON hdi4.id_house_listing = dhl.sk_house_listing
   AND hdi4.dt_day = date(dhl.ts_listing_version_start)
   AND hdi4.dt_day >= date('2025-08-01')
WHERE date(qs.listing_start_dt) >= date('2025-08-01')
  AND dhl.listing_category_start IN ('Re-Listing', 'Recovered')
  AND qs.time_completed_4w = TRUE
  AND bs.is_3p_fr = '1P'
  AND NOT (EXTRACT(MONTH FROM qs.listing_start_dt) = 8 AND hdi4.rent IS NULL)
GROUP BY 1
ORDER BY 1 DESC
```

For **weekly** views, group by `listing_start_week` instead of `listing_start_mth`.

### Query 3 — OL snapshot: well priced / overpriced share by FL / RL / RC (RENT)

**Ongoing Listings stock** — currently **PUBLISHED** rent listing versions, classified at **latest price** vs **p90**.

```sql
WITH latest_prediction AS (
    SELECT
        pp.id_house,
        pp.business_context,
        pp.p90,
        ROW_NUMBER() OVER (
            PARTITION BY pp.id_house, pp.business_context
            ORDER BY pp.ts_created DESC
        ) AS rn
    FROM datalake_pricing_clean.price_prediction AS pp
    WHERE pp.business_context = 'RENT'
),
priced_listings AS (
    SELECT
        dhl.sk_house_listing,
        CASE dhl.listing_category_start
            WHEN 'First Listing' THEN 'FL'
            WHEN 'Re-Listing' THEN 'RL'
            WHEN 'Recovered' THEN 'RC'
            ELSE dhl.listing_category_start
        END AS nl_segment,
        dp.price,
        lp.p90,
        CASE
            WHEN dp.price IS NULL OR lp.p90 IS NULL THEN 'unknown'
            WHEN dp.price > lp.p90 THEN 'overpriced'
            ELSE 'well_priced'
        END AS pricing_status
    FROM dw_rent.dim_house_listing AS dhl
    INNER JOIN dw_listing.fact_price_changes AS fpc
        ON dhl.id_house = fpc.sk_house
    INNER JOIN dw_listing.dim_pricing AS dp
        ON fpc.sk_pricing = dp.sk_pricing
       AND dp.business_context = 'RENT'
       AND dp.is_last_price = TRUE
    INNER JOIN latest_prediction AS lp
        ON fpc.sk_house = lp.id_house
       AND lp.business_context = 'RENT'
       AND lp.rn = 1
    WHERE dhl.version <> 0
      AND dhl.status IN ('PUBLISHED', 'publicado')
      AND dhl.country_code = 'BR'
)
SELECT
    'OL' AS listing_slice,
    nl_segment,
    pricing_status,
    COUNT(DISTINCT sk_house_listing) AS n_listings,
    1.000 * COUNT(DISTINCT sk_house_listing)
        / SUM(COUNT(DISTINCT sk_house_listing)) OVER (PARTITION BY nl_segment) AS share_within_segment
FROM priced_listings
WHERE pricing_status IN ('well_priced', 'overpriced')
GROUP BY 1, 2, 3
ORDER BY 2, 3
```

### Query 4 — NL cohort: FL2WP / RL2WP / RC2WP (Pub, monthly, 1P, BR)

**New Listings** published in each month — official **`price_score_pub`** from `listing_scores`, broken by category.

```sql
WITH base_supply AS (
    SELECT DISTINCT
        obt.sk_house,
        CASE
            WHEN upper(obt.planning_operation) = 'REDE' THEN '3P REDE'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.nm_business_context = 'RENT'
                 AND obt.sk_user_conversion IN (8919771, 11299701, 6001450) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.nm_business_context = 'RENT'
                 AND lower(obt.nm_agent) IN ('ciq_pj', '3p_fr') THEN '3P Operations'
            ELSE '1P'
        END AS is_3p_fr
    FROM dw_growth.obt_supply AS obt
    WHERE obt.nm_business_context = 'RENT'
      AND obt.country_code = 'BR'
      AND obt.cd_funnel_step = 'first_listing'
      AND obt.date < current_date
)
SELECT
    'NL' AS listing_slice,
    CAST(qs.listing_start_mth AS DATE) AS cohort_period,
    CASE dhl.listing_category_start
        WHEN 'First Listing' THEN 'FL'
        WHEN 'Re-Listing' THEN 'RL'
        WHEN 'Recovered' THEN 'RC'
        ELSE dhl.listing_category_start
    END AS nl_segment,
    COUNT(DISTINCT qs.sk_house_listing) AS total_listings,
    COUNT(DISTINCT CASE WHEN qs.price_score_pub = 1 THEN qs.sk_house_listing END) AS well_priced_listings,
    COUNT(DISTINCT CASE WHEN qs.price_score_pub = 0 THEN qs.sk_house_listing END) AS overpriced_listings,
    1.000 * SUM(qs.price_score_pub)
        / NULLIF(COUNT(DISTINCT qs.sk_house_listing), 0) AS l2wp_pub_rate
FROM sandbox.listing_scores AS qs
INNER JOIN dw_rent.dim_house_listing AS dhl
    ON qs.sk_house_listing = dhl.sk_house_listing
INNER JOIN base_supply AS bs
    ON dhl.id_house = bs.sk_house
WHERE date(qs.listing_start_dt) >= date('2025-08-01')
  AND dhl.listing_category_start IN ('First Listing', 'Re-Listing', 'Recovered')
  AND bs.is_3p_fr = '1P'
GROUP BY 1, 2, 3
ORDER BY 2 DESC, 3
```

**SALE NL:** same OL pricing rule on `dim_pricing` + `p70`, cohort = first publications in period — see `metric_entities/first_listings_1p.md`; no RL/RC breakdown.

### Query 5 — L2R by well priced / overpriced (RENT, monthly cohort, ever signed)

**Preferred** — pricing tier from **`price_score_pub`** at publication; L2R formula from `listing_to_rental.md`.

```sql
WITH listing_pricing AS (
    SELECT
        qs.sk_house_listing,
        CASE
            WHEN qs.price_score_pub = 1 THEN 'well_priced'
            WHEN qs.price_score_pub = 0 THEN 'overpriced'
            ELSE 'unknown'
        END AS pricing_status
    FROM sandbox.listing_scores AS qs
),
cohort AS (
    SELECT
        DATE_TRUNC('month', dhl.ts_publication) AS cohort_period,
        dhl.country_code,
        dhl.sk_house_listing,
        lp.pricing_status,
        fhl.sk_contract
    FROM dw_rent.dim_house_listing AS dhl
    INNER JOIN listing_pricing AS lp
        ON lp.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN dw_rent.fact_house_listings AS fhl
        ON fhl.sk_house_listing = dhl.sk_house_listing
    WHERE dhl.ts_publication IS NOT NULL
      AND lp.pricing_status IN ('well_priced', 'overpriced')
)
SELECT
    cohort_period,
    country_code,
    pricing_status,
    COUNT(DISTINCT sk_house_listing) AS total_listings,
    COUNT(DISTINCT sk_contract) AS contracts_signed,
    CAST(COUNT(DISTINCT sk_contract) AS DOUBLE)
        / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS l2r
FROM cohort
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2, 3
```

Add `listing_category_start`, 1P filters, or date bounds as needed. For **L2R 4W/8W**, add `days_listing_to_contract_signed <= 28/56` on converted rows — see `listing_to_rental.md` Query 3.

### Query 6 — L2CCV by well priced / overpriced (SALE, 8W from publication)

Pricing at **first publication** vs **p70**; L2CCV pattern from `listing_demand_funnel_conversions.md`.

```sql
WITH latest_prediction AS (
    SELECT
        pp.id_house,
        pp.p70,
        ROW_NUMBER() OVER (
            PARTITION BY pp.id_house
            ORDER BY pp.ts_created DESC
        ) AS rn
    FROM datalake_pricing_clean.price_prediction AS pp
    WHERE pp.business_context = 'SALE'
),
listing_pub AS (
    SELECT
        dl.sk_sale_listing,
        dl.sk_house,
        CAST(dl.ts_first_publication AS DATE) AS publication_date,
        DATE_TRUNC('month', dl.ts_first_publication) AS cohort_month,
        publication_date + INTERVAL '8' WEEK AS window_end_8w
    FROM dw_sale.dim_listing AS dl
    WHERE dl.ts_first_publication IS NOT NULL
),
pub_price AS (
    SELECT
        lp.sk_sale_listing,
        dp.price,
        ROW_NUMBER() OVER (
            PARTITION BY lp.sk_sale_listing
            ORDER BY fpc.ts_price_started DESC
        ) AS rn
    FROM listing_pub AS lp
    INNER JOIN dw_listing.fact_price_changes AS fpc
        ON fpc.sk_house = lp.sk_house
    INNER JOIN dw_listing.dim_pricing AS dp
        ON fpc.sk_pricing = dp.sk_pricing
       AND dp.business_context = 'SALE'
    WHERE CAST(fpc.ts_price_started AS DATE) <= lp.publication_date
),
listing_pricing AS (
    SELECT
        lp.sk_sale_listing,
        lp.sk_house,
        lp.cohort_month,
        lp.publication_date,
        lp.window_end_8w,
        CASE
            WHEN pp.price IS NULL OR pred.p70 IS NULL THEN 'unknown'
            WHEN pp.price > pred.p70 THEN 'overpriced'
            ELSE 'well_priced'
        END AS pricing_status
    FROM listing_pub AS lp
    LEFT JOIN pub_price AS pp
        ON pp.sk_sale_listing = lp.sk_sale_listing
       AND pp.rn = 1
    LEFT JOIN latest_prediction AS pred
        ON pred.id_house = lp.sk_house
       AND pred.rn = 1
),
listing_ccv AS (
    SELECT
        lpr.sk_sale_listing,
        lpr.cohort_month,
        lpr.pricing_status,
        MIN(sa.ts_sale_agreement_signed) AS ts_ccv
    FROM listing_pricing AS lpr
    LEFT JOIN dw_sale.fact_offers AS fo
        ON fo.sk_house = lpr.sk_house
    LEFT JOIN dw_sale.dim_sale_agreement AS sa
        ON fo.sk_offer = sa.sk_offer
       AND sa.ts_sale_agreement_signed BETWEEN lpr.publication_date AND lpr.window_end_8w
    WHERE lpr.pricing_status IN ('well_priced', 'overpriced')
    GROUP BY 1, 2, 3
)
SELECT
    cohort_month,
    pricing_status,
    COUNT(DISTINCT sk_sale_listing) AS total_listings,
    COUNT(DISTINCT CASE WHEN ts_ccv IS NOT NULL THEN sk_sale_listing END) AS ccv_signed,
    1.000 * COUNT(DISTINCT CASE WHEN ts_ccv IS NOT NULL THEN sk_sale_listing END)
        / NULLIF(COUNT(DISTINCT sk_sale_listing), 0) AS l2ccv_8w
FROM listing_ccv
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

For **12W** or **M0+M1**, extend the window on `ts_sale_agreement_signed` — see `listing_demand_funnel_conversions.md`.

### Query 7 — L2VB by well priced / overpriced (RENT, 4W from publication)

Pricing from **`price_score_pub`**; demand from **`fact_listing_rent_flows`** at **`sk_house_listing`**. Change `INTERVAL '4' WEEK` to **1W / 2W** as needed.

```sql
WITH listing_pricing AS (
    SELECT
        qs.sk_house_listing,
        CASE
            WHEN qs.price_score_pub = 1 THEN 'well_priced'
            WHEN qs.price_score_pub = 0 THEN 'overpriced'
            ELSE 'unknown'
        END AS pricing_status
    FROM sandbox.listing_scores AS qs
),
listing_pub AS (
    SELECT
        dhl.sk_house_listing,
        DATE_TRUNC('month', dhl.ts_publication) AS cohort_month,
        lp.pricing_status,
        CAST(dhl.ts_publication AS DATE) AS publication_date,
        CAST(dhl.ts_publication AS DATE) + INTERVAL '4' WEEK AS window_end_4w
    FROM dw_rent.dim_house_listing AS dhl
    INNER JOIN listing_pricing AS lp
        ON lp.sk_house_listing = dhl.sk_house_listing
    WHERE dhl.ts_publication IS NOT NULL
      AND lp.pricing_status IN ('well_priced', 'overpriced')
),
listing_demand AS (
    SELECT
        lp.sk_house_listing,
        lp.cohort_month,
        lp.pricing_status,
        MAX(CASE
            WHEN rf.sk_booking_created_date > 0
             AND dd_vb.date BETWEEN lp.publication_date AND lp.window_end_4w
            THEN 1 ELSE 0
        END) AS has_vb_4w
    FROM listing_pub AS lp
    LEFT JOIN dw_rent.fact_listing_rent_flows AS rf
        ON rf.sk_house_listing = lp.sk_house_listing
    LEFT JOIN dw_public.dim_date AS dd_vb
        ON dd_vb.sk_date = rf.sk_booking_created_date
    GROUP BY lp.sk_house_listing, lp.cohort_month, lp.pricing_status
)
SELECT
    cohort_month,
    pricing_status,
    COUNT(DISTINCT sk_house_listing) AS cohort_size,
    SUM(has_vb_4w) AS listings_with_vb_4w,
    1.000 * SUM(has_vb_4w) / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS l2vb_4w
FROM listing_demand
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

### Query 8 — L2VB by well priced / overpriced (SALE, 4W from publication)

Reuse **publication pricing** pattern from Query 6; demand from **`fact_visits`** on **`sk_house`**.

```sql
WITH latest_prediction AS (
    SELECT
        pp.id_house,
        pp.p70,
        ROW_NUMBER() OVER (
            PARTITION BY pp.id_house
            ORDER BY pp.ts_created DESC
        ) AS rn
    FROM datalake_pricing_clean.price_prediction AS pp
    WHERE pp.business_context = 'SALE'
),
listing_pub AS (
    SELECT
        dl.sk_sale_listing,
        dl.sk_house,
        CAST(dl.ts_first_publication AS DATE) AS publication_date,
        DATE_TRUNC('month', dl.ts_first_publication) AS cohort_month,
        publication_date + INTERVAL '4' WEEK AS window_end_4w
    FROM dw_sale.dim_listing AS dl
    WHERE dl.ts_first_publication IS NOT NULL
),
pub_price AS (
    SELECT
        lp.sk_sale_listing,
        dp.price,
        ROW_NUMBER() OVER (
            PARTITION BY lp.sk_sale_listing
            ORDER BY fpc.ts_price_started DESC
        ) AS rn
    FROM listing_pub AS lp
    INNER JOIN dw_listing.fact_price_changes AS fpc
        ON fpc.sk_house = lp.sk_house
    INNER JOIN dw_listing.dim_pricing AS dp
        ON fpc.sk_pricing = dp.sk_pricing
       AND dp.business_context = 'SALE'
    WHERE CAST(fpc.ts_price_started AS DATE) <= lp.publication_date
),
listing_pricing AS (
    SELECT
        lp.sk_sale_listing,
        lp.sk_house,
        lp.cohort_month,
        lp.publication_date,
        lp.window_end_4w,
        CASE
            WHEN pp.price IS NULL OR pred.p70 IS NULL THEN 'unknown'
            WHEN pp.price > pred.p70 THEN 'overpriced'
            ELSE 'well_priced'
        END AS pricing_status
    FROM listing_pub AS lp
    LEFT JOIN pub_price AS pp
        ON pp.sk_sale_listing = lp.sk_sale_listing
       AND pp.rn = 1
    LEFT JOIN latest_prediction AS pred
        ON pred.id_house = lp.sk_house
       AND pred.rn = 1
    WHERE CASE
            WHEN pp.price IS NULL OR pred.p70 IS NULL THEN 'unknown'
            WHEN pp.price > pred.p70 THEN 'overpriced'
            ELSE 'well_priced'
        END IN ('well_priced', 'overpriced')
),
listing_demand AS (
    SELECT
        lpr.sk_sale_listing,
        lpr.cohort_month,
        lpr.pricing_status,
        MIN(fv.ts_booking_created) FILTER (
            WHERE fv.ts_booking_created BETWEEN lpr.publication_date AND lpr.window_end_4w
        ) AS ts_vb_4w
    FROM listing_pricing AS lpr
    LEFT JOIN dw_sale.fact_visits AS fv
        ON fv.sk_house = lpr.sk_house
    GROUP BY lpr.sk_sale_listing, lpr.cohort_month, lpr.pricing_status
)
SELECT
    cohort_month,
    pricing_status,
    COUNT(DISTINCT sk_sale_listing) AS cohort_size,
    COUNT(DISTINCT CASE WHEN ts_vb_4w IS NOT NULL THEN sk_sale_listing END) AS listings_with_vb_4w,
    1.000 * COUNT(DISTINCT CASE WHEN ts_vb_4w IS NOT NULL THEN sk_sale_listing END)
        / NULLIF(COUNT(DISTINCT sk_sale_listing), 0) AS l2vb_4w
FROM listing_demand
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
