# Listing Performance Score (1P)

## Ownership

**Data Owner:**
- bruna.prates@quintoandar.com.br

**Data Steward:**
- bruna.prates@quintoandar.com.br

## Overview

**Listing Performance Score** (also **Performance Score**, **demand score**) is a **1–5 demand-health score** for **on-market listings**, comparing each house’s recent demand (pageviews, visits booked, offers) to **similar active listings** in the same business context.

The score is **calculated in Data** (DAG **`enrich_similarity_score`**) and forwarded to product systems (SNS → Main `ListingPerformance` → OPL `tb_listing_score`). **For analytics and TARS, the source of truth is the enrich layer** — `datalake_similarity_score.house_metrics_score` and `similar_houses`, implemented in `dags/house_and_listing/enrich_similarity_score/queries/enrich/similar_houses.sql` and `house_metrics_score.sql` — not EBDB, OPL, or ad-hoc demand reconstructions.

**Applies to RENT and SALE** (`business_context`). Grain: **`id_house` + `business_context` + reference day** (daily snapshot).

## Related Business Entities

- House and Listing
- Pricing

## Glossary and Synonyms

- **Listing Performance Score**, **Performance Score**, **score de performance**, **demand score**, **`demand_score`** (product event payload) → **`final_score`** on `house_metrics_score`
- **Performance Hub** — owner-facing UX that displays this score; analytics still use **`datalake_similarity_score.*`**
- **Similar listings** — peer set for comparison → `similar_houses` (`ids_similar`, `similar_rule`)
- **Traffic** (product) → **search results pageviews** (`base_srpv` / `score_srpv`) and **listing pageviews** (`base_lpv` / `score_lpv`) — not a single column
- **Visits scheduled** → **visits booked** (`base_vb` / `score_vb`)
- **Offers** → `base_os` / `score_os` (included in **`final_score`** for both RENT and SALE in the pipeline)
- **`score_favorites`** / **`base_favorites`** — computed in enrich but **excluded from `final_score`** (not in the weighted formula)
- **NOT** `reverse_demand_score` / `listing_demand_score` — different legacy growth pipeline
- **NOT** raw `fact_visits` / Amplitude alone — component inputs only; the **official score** is precomputed in enrich

## Scope

**Included:**

- Houses **on-market** on the reference day (see **Base-house eligibility** below)
- **RENT** and **SALE** — filter `business_context`
- Daily batch from DAG **`enrich_similarity_score`**

**Demand aggregation window** (implemented in `house_metrics_score.sql`):

| Context | Max lookback (`rule_days_published`) | `dt_agg_started` logic |
|---------|--------------------------------------|-------------------------|
| **RENT** | **15 days** | `dt_ended − (min(days_published, 15) − 1)` |
| **SALE** | **30 days** | `dt_ended − (min(days_published, 30) − 1)` |

If the listing is younger than the cap, the window shortens to **`days_published`** (same intent as RFC: compare on comparable tenure).

**Row coverage:**

| Table | Who gets a row |
|-------|----------------|
| **`house_metrics_score`** | **All** published RENT bases + **all** SALE rows in `ongoing_listings_daily_info` for the day — **including** bases with **no** similar set (`ids_similar` / component scores / `final_score` **NULL**) |
| **`similar_houses`** | Only bases in the similarity universe (**RENT** published with `days_published >= 1`; **SALE** with `days_published >= 1` **and** VB in last 30d) where a rule succeeded with **`qty_similar >= 3`** |

**Product UX (RFC):** score shown from **day 3** after publication; updated daily. The enrich tables do **not** enforce day-3 in SQL — filter `days_published >= 3` in analytics when matching the app.

**Excluded (unless explicitly requested):**

- Unpublished / off-market houses on the reference day
- Historical score in **OPL / EBDB** — those stores hold **current state for apps**, not the analytical history in the lake (enrich is daily-partitioned history)

**Grain:** one row per **`id_house` + `business_context` + `year/month/day`**.

---

## Source of truth (TARS routing)

| Need | Table | DAG |
|------|-------|-----|
| **Score + demand components** | **`datalake_similarity_score.house_metrics_score`** | `enrich_similarity_score` |
| **Similar listing peer set** | **`datalake_similarity_score.similar_houses`** | `enrich_similarity_score` |

**Do not use for Performance Score questions:**

| Source | Why not |
|--------|---------|
| EBDB `ListingPerformance`, OPL `tb_listing_score` | Product **current-state** replicas — not lake analytics SoT |
| `reverse_demand_score` / `listing_demand_score` | Legacy **demand score** export — different model |
| Rebuilding from `fact_visits` / `fact_listing_rent_flows` / Amplitude | Component metrics only — **not** the official similarity-based score |
| `sandbox.listing_scores` | Supply **quality** (pricing levers) — see `supply_quality_score.md` / `listing_to_well_priced.md` |

**Join to listing dims:** `id_house` = `dim_house_listing.id_house` / `dim_house.sk_house` — score is **house + context**, not `sk_house_listing` version.

---

## Calculation

### Input tables (pipeline)

| Role | RENT | SALE |
|------|------|------|
| Daily listing metrics | `datalake_rental_historical_follow_up.house_listings_daily_info` | `datalake_sale_ongoing_listings.ongoing_listings_daily_info` |
| House attrs (city, type, area, geo) | `datalake_ebdb_listing.house` | same |
| Price / percentiles (similarity) | `hldi.rent`, `p_10`, `p_70`, `p_90` | `sale_price`, `calculator_min_price`, `calculator_p70_price`, `calculator_max_price` |

### Base-house eligibility

| Context | Row in `house_metrics_score` | Can get non-NULL `final_score` (in `similar_houses` universe) |
|---------|------------------------------|----------------------------------------------------------------|
| **RENT** | `status_history = 'PUBLISHED'` on reference day | Same — must also match a similarity rule with **≥ 3** peers |
| **SALE** | Any house in `ongoing_listings_daily_info` for the day | **`days_published >= 1`** **and** ≥ **1 visit booked in the last 30 days** (`sale_with_visits` — **not in RFC**) |

SALE houses **without** recent VB may still appear in **`house_metrics_score`** with **`final_score` NULL** (no peer set). The VB gate applies to **similarity matching**, not to whether the base row exists.

### Similar listings (`similar_houses`)

Built daily per **base** house on the **same snapshot** (`year`, `month`, `day`). A **candidate similar** must satisfy **all** of:

| Filter | Rule |
|--------|------|
| Identity | `id_house ≠ base`, same **`business_context`**, same **`city`**, same **`type`** (`house.type`) |
| Well priced | Candidate price **≤ p70** (`is_below_predicted_price_70`) — similars must be well priced |
| Publication tenure | `similar.days_published >= min(base.days_published, rule_days)` — **15** (RENT) / **30** (SALE) |
| SALE visits | Candidate must have **≥ 1 VB in last 30 days**; RENT candidates skip this (`COALESCE(..., TRUE)`) |

**Price / area band (rules 1–2 only — pipeline, not RFC ±30%):**

- Candidate **listed price** must fall in **`[base.p_10, base.p_90]`** (calculator percentiles on the base house), **not** ±30% of base listed price
- Candidate **area** within **`base.total_area × [0.7, 1.3]`**

**Three-tier rule selection** — pick the **strictest rule that yields ≥ 3 similars** (lowest `rule_id` wins; text in **`similar_rule`**):

| Rule | Extra constraints | Min peers |
|------|-------------------|-----------|
| **1** | Price in base **p10–p90** + area ±30% + haversine **≤ 2 km** | **3** |
| **2** | Price in base **p10–p90** + area ±30% + haversine **≤ 5 km** | **3** |
| **3** | **Fallback** — drops price band, area, and distance; keeps city/type/context, **p70**, publication tenure, SALE VB rule | **3** |

RFC mentions 2 km / 5 km when &lt; 5 peers; the pipeline adds an explicit **rule 3 fallback** without geo/price/area — **only in SQL**.

If **no** rule reaches 3 similars: base is **absent** from `similar_houses`; `house_metrics_score.final_score` is **NULL**.

Full rule text is stored in column **`similar_rule`**.

### Metric scores (1–5 each)

For each demand metric, sum activity over **`[dt_agg_started, dt_agg_ended]`** for the base and for each similar listing; then take the **median (P50)** of per-similar totals:

```
similar_* = PERCENTILE(sum_metric_per_similar, 0.5)
calculation_score_* = ROUND((base_* + 1) / (similar_* + 1), 1)   -- +1 smoothing (pipeline)
```

| `calculation_score_*` | `score_*` |
|-----------------------|-----------|
| ≥ 1.5 | **5** |
| ≥ 1.1 | **4** |
| ≤ 0.5 | **1** |
| ≤ 0.9 | **2** |
| else | **3** |

**Metrics in `final_score`:** **`srpv`**, **`lpv`**, **`vb`**, **`os`** → `score_srpv`, `score_lpv`, `score_vb`, `score_os`.

**Computed but not weighted:** **`favorites`** (`score_favorites`, `base_favorites`) — present in the table, **excluded from `final_score`**.

Rule strings are persisted on each row: **`score_calculation_rule`**, **`score_metric_rule`**, **`similar_metric_rule`**.

### Final score (`final_score`)

**Pipeline formula** (same for **RENT and SALE** — see **`final_score_rule`** column):

```
final_score = ROUND((score_srpv * 2 + score_lpv * 3 + score_vb * 1 + score_os * 1) / 7)
```

Integer **1 (bad) … 5 (very good)**. **`NULL`** when `ids_similar IS NULL`.

**RFC vs pipeline (do not mix):**

| Topic | RFC (product doc) | Pipeline (`enrich_similarity_score`) |
|-------|-------------------|--------------------------------------|
| SALE `final_score` denominator | **/6** without OS | **/7** with **`score_os`** |
| Similar price band | ±**30%** vs base price | Base **`p10–p90`** band |
| Rule 3 fallback | Not described | City/type/p70/tenure only, ≥ 3 peers |
| SALE base eligibility | On-market listings | **Scored** only if **VB in last 30d** + `days_published >= 1`; row may exist without score |
| Favorites in score | Not in RFC formula | Column exists; **not** in `final_score` |
| Day-3 gate | UX shows from day 3 | Not filtered in SQL — apply in queries |

**Product event mapping:** `demand_score` in `ListingPerformanceScoreEvents` = **`final_score`**.

### Median flags (product UX)

RFC flags **`ABOVE_MEDIAN` / `BELOW_MEDIAN` / `ON_MEDIAN`** compare counts to similar medians. Analytical proxy from enrich:

| Flag logic (per metric) | Condition on `calculation_score_*` |
|-------------------------|----------------------------------|
| **ABOVE_MEDIAN** | &gt; 1.1 |
| **BELOW_MEDIAN** | &lt; 0.9 |
| **ON_MEDIAN** | otherwise |

---

## Dos and Don'ts

**Do:**

- Route **all Performance Score questions** to this file and **`datalake_similarity_score.house_metrics_score`**
- Always filter **`year`, `month`, `day`** partitions (and `business_context`)
- Use **`final_score`** as the score column; report **`NULL`** rate when no similars
- Join **`similar_houses`** when the question needs the peer list, **`similar_rule`**, or `qty_similar`
- Distinguish **RENT vs SALE** — different windows (15 vs 30 days) and **SALE-only base VB gate**
- Cite **pipeline SQL** when explaining rules — read **`similar_rule`** / **`final_score_rule`** columns for the exact string used on a row
- Filter **`days_published >= 3`** when matching **product UX** day-3 display

**Don't:**

- Answer from **EBDB / OPL** tables for lake analytics
- Use **`reverse_demand_score`** or **`listing_demand_score`** as Performance Score
- Recompute the score from raw visits/pageviews without the **similarity** pipeline
- Confuse with **L2Wp / Quality Pub** (`sandbox.listing_scores`) — pricing-quality, not demand performance
- Scan `house_metrics_score` without **partition filters**
- Describe similar-listing price band as **±30%** — pipeline uses **base p10–p90**
- Assume **`similar_houses` has every scored house** — only bases with **≥ 3** peers; others appear only in `house_metrics_score` with **NULL** `final_score`
- Use **`score_favorites`** in the weighted **`final_score`** — it is not part of the formula

---

## Golden Queries

### Query 1 — Latest performance score for a house (RENT or SALE)

```sql
SELECT
    hms.id_house,
    hms.business_context,
    MAKE_DATE(hms.year, hms.month, hms.day) AS score_date,
    hms.final_score,
    hms.score_srpv,
    hms.score_lpv,
    hms.score_vb,
    hms.score_os,
    hms.base_srpv,
    hms.base_lpv,
    hms.base_vb,
    hms.base_os,
    hms.base_favorites,
    hms.score_favorites,
    hms.calculation_score_lpv,
    hms.final_score_rule,
    hms.similar_metric_rule,
    hms.dt_agg_started,
    hms.dt_agg_ended,
    hms.ids_similar IS NOT NULL AS has_similar_set
FROM datalake_similarity_score.house_metrics_score AS hms
WHERE hms.id_house = 12345678
  AND hms.business_context = 'RENT'
  AND hms.year = 2026
  AND hms.month = 7
  AND hms.day = 3
```

For “**current** score”, use the **latest available** `year/month/day` partition instead of hard-coding.

### Query 2 — Score distribution by day (RENT, BR houses)

```sql
SELECT
    MAKE_DATE(hms.year, hms.month, hms.day) AS score_date,
    hms.final_score,
    COUNT(*) AS n_houses
FROM datalake_similarity_score.house_metrics_score AS hms
INNER JOIN dw_house.dim_house AS dh
    ON hms.id_house = dh.sk_house
INNER JOIN dw_public.dim_region AS dr
    ON dh.sk_region = dr.sk_region
WHERE hms.business_context = 'RENT'
  AND dr.country_code = 'BR'
  AND hms.year = 2026
  AND hms.month = 7
  AND hms.final_score IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2
```

### Query 3 — Base house with similar peer count

```sql
SELECT
    hms.id_house,
    hms.business_context,
    MAKE_DATE(hms.year, hms.month, hms.day) AS score_date,
    hms.final_score,
    sh.qty_similar,
    sh.similar_rule
FROM datalake_similarity_score.house_metrics_score AS hms
LEFT JOIN datalake_similarity_score.similar_houses AS sh
    ON hms.id_house = sh.id_house
   AND hms.business_context = sh.business_context
   AND hms.year = sh.year
   AND hms.month = sh.month
   AND hms.day = sh.day
WHERE hms.id_house = 12345678
  AND hms.business_context = 'SALE'
  AND hms.year = 2026
  AND hms.month = 7
  AND hms.day = 3
```

## DataHub catalog

> Added automatically by the agent after Step 7 — do not fill in manually.
