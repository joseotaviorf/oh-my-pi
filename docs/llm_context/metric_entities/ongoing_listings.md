# Ongoing Listings (Daily Volume)

## Ownership

**Data Owner:**
- bruna.prates@quintoandar.com.br

**Data Steward:**
- bruna.prates@quintoandar.com.br

## Overview

**Ongoing Listings** is the daily count of listings with active **PUBLISHED** status on each calendar day — published inventory (supply stock), not demand or distinct houses.

The metric exists for **both For Rent (RENT) and For Sale (SALE)**, but **implementation differs by business context**. Always confirm `RENT` vs `SALE` before picking tables, keys, and SQL.

| Context | Source of truth | Listing key | Materialized table? |
|---------|-----------------|-------------|---------------------|
| **RENT** | Validated SQL on `fact_house_listing_status` + bounded `dim_date` spine | `sk_house_listing` | No — former metrics table deprecated; **run the query** (see **TARS / interactive execution**) |
| **SALE** | `dw_sale.fact_daily_ongoing_listing` | `sk_sale_listing` | Yes — one row per published listing per day |

## Related Domain Entities

- House and Listing

## Catalog

| Metric | Type |
| :---- | :---- |
| Ongoing Listings | Health Metric |

## Glossary and Synonyms

- **Ongoing listings**, **ongoing listing volume**, **estoque publicado**, **anúncios ativos**, **published inventory** → this metric (daily grain)
- **Listings ativos (aluguel / venda)** → specify business context

## Scope (shared)

**Included:** listings with **PUBLISHED** status active on the reference day (per context rules below).

**Excluded:** non-published statuses (EDITING, SUSPENDED, UNPUBLISHED, OPTED_OUT, …).

**Do not mix contexts** in one query without normalizing keys and filters.

---

## Calculation

RENT and SALE are counted independently and are never summed into a single number:

```
Ongoing Listings RENT (day D) = COUNT(DISTINCT sk_house_listing)
Ongoing Listings SALE (day D) = COUNT(DISTINCT sk_sale_listing)
```

RENT has no materialized metrics table — it is computed on demand by exploding PUBLISHED status intervals against `dim_date`, then deduplicating to the latest `ts_status_start` per listing per day. SALE reads the pre-materialized daily snapshot in `dw_sale.fact_daily_ongoing_listing`, one row per listing per PUBLISHED day.

Each context has its own canonical filter — see [Canonical filter (RENT)](#canonical-filter-rent) and [Canonical filter (SALE)](#canonical-filter-sale) for the exact predicates.

---

## For Rent (RENT)

### What counts

Each day **D**, count distinct **`sk_house_listing`** (rent listing version) with an active PUBLISHED status interval, after:

1. **Exclusive end-day** interval via `dim_date` (see below)
2. `dim_house_listing.version <> 0`
3. `dim_region.city_group IS NOT NULL`
4. Same-day dedup: latest `ts_status_start` per listing per day (`ROW_NUMBER()` ranked per listing/day)

```
Ongoing Listings RENT (day D) = COUNT(DISTINCT sk_house_listing)
```

**Source of truth:** validated SQL below. No materialized metrics table — the query **is** the metric.

### Status interval (RENT — critical)

```sql
d.date BETWEEN COALESCE(DATE(fhls.ts_status_start), DATE '2000-01-01')
         AND COALESCE(DATE_ADD('day', -1, DATE(fhls.ts_status_end)), CURRENT_DATE)
```

Do **not** use simplified `ts_status_start ≤ day AND ts_status_end IS NULL OR ≥ day` — it is not the official definition.

On Databricks, add the `RANGE_JOIN(fhls, 800)` hint when exploding intervals. Trino has no equivalent hint — the golden query below runs the range join directly.

### Canonical filter (RENT)

```sql
fhls.status_history IN ('publicado', 'PUBLISHED')
AND dhl.version <> 0
AND dr.city_group IS NOT NULL
-- AND fhls.country_code = 'BR'   -- when country-specific
```

### RENT nuances

- **Multi-country:** group by `country_code` (BR, MX, …).
- **1P vs 3P:** optional; join `dim_house_listing.is_rent_3p_supply` when segmenting.
- **`house_listings_daily_info`** — partitioned daily snapshot useful for demand ratios and PP Multi; **not** source of truth for official ongoing-listings volume (different grain/edge cases). Do not substitute for this metric.

### TARS / interactive execution (RENT — mandatory)

The validated definition explodes PUBLISHED intervals against `dim_date`. **Joining `fact_house_listing_status` to all of `dim_date` before bounding the requested window will time out** in interactive Trars (~45s).

**Always apply these rules when executing RENT ongoing listings:**

1. **Confirm RENT vs SALE** — SALE uses `fact_daily_ongoing_listing` (fast, partitioned).
2. **Bound the date window first** in a `date_spine` CTE — never scan full `dim_date` history.
3. **Partition-prune `fact_house_listing_status`** with `country_code = 'BR'` (or requested country) in `WHERE`.
4. **Pre-filter status intervals** that overlap the window before joining `date_spine`:
   - `DATE(ts_status_start) <= end_of_window`
   - `COALESCE(DATE_ADD('day', -1, DATE(ts_status_end)), CURRENT_DATE) >= start_of_window`
5. **Default window when the user says “visão diária” without a range:** last **30 calendar days** ending yesterday; state the assumption. **Max ~90 days** per interactive query — for longer history, recommend a batch job outside TARS.
6. **Do not retry** the same full-history pattern after timeout — rewrite with the bounded pattern below.

**Answering “Me dê uma visão diária do volume de ongoing listings”:**

- If context unspecified, ask **RENT vs SALE** or run both sections separately.
- **RENT:** bounded golden query below (not unfiltered `dim_date` join).
- **SALE:** golden query with `year` / `month` / `day` partition filters.

---

## For Sale (SALE)

### What counts

Each day **D**, count distinct **`sk_sale_listing`** that appear in the daily published-inventory snapshot. The pipeline (`dw_sale_ongoing_listings`) materializes one row per listing per PUBLISHED day into **`dw_sale.fact_daily_ongoing_listing`**.

```
Ongoing Listings SALE (day D) = COUNT(DISTINCT sk_sale_listing)
FROM dw_sale.fact_daily_ongoing_listing
WHERE snapshot day = D
```

**Source of truth:** read the fact table — do not re-derive from status history in ad-hoc SQL unless validating pipeline logic.

### How the snapshot is built (reference)

- Status history from LBC audit (`listing_business_context_aud`, `business_context = 'SALE'`)
- Explode to days where `status = 'PUBLISHED'`
- Dedup: one row per **`sk_house`** per day (latest status start that day)
- PK `sk_snapshot` = `sk_house` × date key; carries `sk_sale_listing`, demand metrics, price fields

Interval semantics in the **pipeline** differ from RENT (inclusive end on `dim_date` join) — for **volume**, trust the fact table.

### Canonical filter (SALE)

Always partition-prune:

```sql
MAKE_DATE(fdol.year, fdol.month, fdol.day) = <reference_day>
-- or BETWEEN for ranges
```

Optional geographic scope:

```sql
JOIN dw_public.dim_region AS dr ON fdol.sk_region = dr.sk_region
WHERE dr.city_group IS NOT NULL
```

Add `country_code` via `dim_region` when country-specific.

### SALE nuances

- Table includes **demand columns** (`qt_visits_booked`, etc.) — summing those is **not** total platform demand (events can occur off published days); use `fact_sale_demand_event` for full demand.
- **3P:** `sk_broker`, `sk_company` on the fact for broker/Rede cuts.
- Grain for volume is **`sk_sale_listing`**, not `sk_house` (pipeline dedups by house when building the snapshot).

---

## Golden Queries

### Golden Query — RENT daily volume (bounded — use in TARS)

**Replace the date bounds** (`start_day`, `end_day`). Default for “visão diária” without range: last 30 days.

```sql
WITH date_spine AS (
    SELECT d.date
    FROM dw_public.dim_date AS d
    WHERE d.date BETWEEN DATE '2026-07-01' AND DATE '2026-07-30'  -- start_day, end_day
),
published_intervals AS (
    SELECT
        fhls.sk_house_listing,
        fhls.country_code,
        fhls.sk_region,
        fhls.ts_status_start,
        COALESCE(DATE(fhls.ts_status_start), DATE '2000-01-01') AS interval_start,
        COALESCE(DATE_ADD('day', -1, DATE(fhls.ts_status_end)), CURRENT_DATE) AS interval_end
    FROM dw_rent.fact_house_listing_status AS fhls
    WHERE fhls.country_code = 'BR'
      AND fhls.status_history IN ('publicado', 'PUBLISHED')
      AND COALESCE(DATE(fhls.ts_status_start), DATE '2000-01-01') <= (SELECT MAX(date) FROM date_spine)
      AND COALESCE(DATE_ADD('day', -1, DATE(fhls.ts_status_end)), CURRENT_DATE) >= (SELECT MIN(date) FROM date_spine)
),
exploded AS (
    SELECT
        pi.sk_house_listing,
        pi.country_code,
        ds.date,
        ROW_NUMBER() OVER (
            PARTITION BY pi.sk_house_listing, ds.date
            ORDER BY pi.ts_status_start DESC
        ) AS rn
    FROM published_intervals AS pi
    INNER JOIN dw_rent.dim_house_listing AS dhl
        ON pi.sk_house_listing = dhl.sk_house_listing
    INNER JOIN dw_public.dim_region AS dr
        ON pi.sk_region = dr.sk_region
    INNER JOIN date_spine AS ds
        ON ds.date BETWEEN pi.interval_start AND pi.interval_end
    WHERE dhl.version <> 0
      AND dr.city_group IS NOT NULL
),
ongoing_listings AS (
    SELECT sk_house_listing, country_code, date
    FROM exploded
    WHERE rn = 1
)
SELECT
    date AS day,
    country_code,
    COUNT(DISTINCT sk_house_listing) AS ongoing_listings
FROM ongoing_listings
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

On Databricks batch jobs (not TARS), add `RANGE_JOIN(fhls, 800)` on the interval join when exploding full history.

### Golden Query — RENT daily volume (reference — full series, batch only)

**Do not run in TARS** — joins all history before filtering. For pipeline validation or async batch only:

```sql
WITH exploded AS (
    SELECT
        fhls.sk_house_listing,
        fhls.country_code,
        d.date,
        ROW_NUMBER() OVER (
            PARTITION BY fhls.sk_house_listing, d.date
            ORDER BY fhls.ts_status_start DESC
        ) AS rn
    FROM dw_rent.fact_house_listing_status AS fhls
    JOIN dw_rent.dim_house_listing AS dhl
        ON fhls.sk_house_listing = dhl.sk_house_listing
    JOIN dw_public.dim_region AS dr
        ON fhls.sk_region = dr.sk_region
    JOIN dw_public.dim_date AS d
        ON d.date BETWEEN COALESCE(DATE(fhls.ts_status_start), DATE '2000-01-01')
            AND COALESCE(DATE_ADD('day', -1, DATE(fhls.ts_status_end)), CURRENT_DATE)
    -- Add AND fhls.country_code = 'BR' when the question is Brazil-only.
    WHERE fhls.status_history IN ('publicado', 'PUBLISHED')
      AND dhl.version <> 0
      AND dr.city_group IS NOT NULL
),
ongoing_listings AS (
    -- Same-day dedup: keep the latest status interval per listing per day.
    SELECT sk_house_listing, country_code, date
    FROM exploded
    WHERE rn = 1
)
SELECT
    date AS day,
    country_code,
    COUNT(DISTINCT sk_house_listing) AS ongoing_listings
FROM ongoing_listings
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

### Golden Query — SALE daily volume

```sql
SELECT
    MAKE_DATE(fdol.year, fdol.month, fdol.day) AS day,
    dr.country_code,
    COUNT(DISTINCT fdol.sk_sale_listing) AS ongoing_listings
FROM dw_sale.fact_daily_ongoing_listing AS fdol
JOIN dw_public.dim_region AS dr
    ON fdol.sk_region = dr.sk_region
-- Add AND dr.country_code = 'BR' when the question is Brazil-only.
WHERE dr.city_group IS NOT NULL
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

Filter `year`, `month`, `day` (or `MAKE_DATE`) for partition pruning on large scans.

---

## Dos and Don'ts

**Do:**

- Ask **RENT vs SALE** first — different source, key, and rules
- **RENT (TARS):** use the **bounded** `date_spine` + interval-overlap query — never full-history `dim_date` join
- **RENT:** always filter `fhls.country_code` and bound the date window (default last 30 days when unspecified)
- **SALE:** count from `fact_daily_ongoing_listing` with `year` / `month` / `day` partition filters
- Report volume at listing-key grain (`sk_house_listing` / `sk_sale_listing`)
- State the date window used when defaulting the range

**Don't:**

- Don't use one SQL for both contexts
- **RENT:** don't join `dim_date` over full history before filtering dates — causes interactive timeout
- **RENT:** don't look for a materialized metrics table; don't use `house_listings_daily_info` for official volume
- **RENT:** don't recommend “batch only” without first trying the bounded golden query
- **SALE:** don't reimplement status explosion ad hoc unless validating the pipeline
- Don't equate `dim_house_listing.status = 'PUBLISHED'` with the **daily historical series** — that is current state, not daily volume
- Don't count `sk_house` without understanding listing grain and dedup rules per context

