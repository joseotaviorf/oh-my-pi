# Ongoing Listings (Daily Volume)

## Overview

**Ongoing Listings** is the daily count of listings with active **PUBLISHED** status on each calendar day — published inventory (supply stock), not demand or distinct houses.

The metric exists for **both For Rent (RENT) and For Sale (SALE)**, but **implementation differs by business context**. Always confirm `RENT` vs `SALE` before picking tables, keys, and SQL.

| Context | Source of truth | Listing key | Materialized table? |
|---------|-----------------|-------------|---------------------|
| **RENT** | Validated SQL on `fact_house_listing_status` + `dim_date` | `sk_house_listing` | No — former metrics table deprecated; **run the query** |
| **SALE** | `dw_sale.fact_daily_ongoing_listing` | `sk_sale_listing` | Yes — one row per published listing per day |

## Related Business Entities

- House and Listing

## Glossary and Synonyms

- **Ongoing listings**, **ongoing listing volume**, **estoque publicado**, **anúncios ativos**, **published inventory** → this metric (daily grain)
- **Listings ativos (aluguel / venda)** → specify business context

## Scope (shared)

**Included:** listings with **PUBLISHED** status active on the reference day (per context rules below).

**Excluded:** non-published statuses (EDITING, SUSPENDED, UNPUBLISHED, OPTED_OUT, …).

**Do not mix contexts** in one query without normalizing keys and filters.

---

## For Rent (RENT)

### What counts

Each day **D**, count distinct **`sk_house_listing`** (rent listing version) with an active PUBLISHED status interval, after:

1. **Exclusive end-day** interval via `dim_date` (see below)
2. `dim_house_listing.version <> 0`
3. `dim_region.city_group IS NOT NULL`
4. Same-day dedup: latest `ts_status_start` per listing per day (`QUALIFY ROW_NUMBER()`)

```
Ongoing Listings RENT (day D) = COUNT(DISTINCT sk_house_listing)
```

**Source of truth:** validated SQL below. No materialized metrics table — the query **is** the metric.

### Status interval (RENT — critical)

```sql
d.date BETWEEN COALESCE(DATE(fhls.ts_status_start), DATE '2000-01-01')
         AND COALESCE(DATE_ADD(DATE(fhls.ts_status_end), -1), CURRENT_DATE)
```

Do **not** use simplified `ts_status_start ≤ day AND ts_status_end IS NULL OR ≥ day` — it is not the official definition.

On Trino, use `RANGE_JOIN(fhls, 800)` when exploding intervals.

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
- **`house_listings_daily_info`** and visits-booked **ratio** metrics use a different path — not source of truth for volume.

### Golden Query — RENT daily volume

```sql
WITH ongoing_listings AS (
    SELECT /*+ RANGE_JOIN(fhls, 800) */
        fhls.sk_house_listing,
        fhls.country_code,
        d.date
    FROM dw_rent.fact_house_listing_status AS fhls
    JOIN dw_rent.dim_house_listing AS dhl
        ON fhls.sk_house_listing = dhl.sk_house_listing
    JOIN dw_public.dim_region AS dr
        ON fhls.sk_region = dr.sk_region
    JOIN dw_public.dim_date AS d
        ON d.date BETWEEN COALESCE(DATE(fhls.ts_status_start), DATE '2000-01-01')
            AND COALESCE(DATE_ADD(DATE(fhls.ts_status_end), -1), CURRENT_DATE)
    WHERE fhls.status_history IN ('publicado', 'PUBLISHED')
      AND dhl.version <> 0
      AND dr.city_group IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fhls.sk_house_listing, d.date
        ORDER BY fhls.ts_status_start DESC
    ) = 1
)
SELECT
    date AS day,
    country_code,
    COUNT(DISTINCT sk_house_listing) AS ongoing_listings
FROM ongoing_listings
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

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

### Golden Query — SALE daily volume

```sql
SELECT
    MAKE_DATE(fdol.year, fdol.month, fdol.day) AS day,
    dr.country_code,
    COUNT(DISTINCT fdol.sk_sale_listing) AS ongoing_listings
FROM dw_sale.fact_daily_ongoing_listing AS fdol
JOIN dw_public.dim_region AS dr
    ON fdol.sk_region = dr.sk_region
WHERE dr.city_group IS NOT NULL
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

Add `AND dr.country_code = 'BR'` when the question is Brazil-only. Filter `year`, `month`, `day` (or `MAKE_DATE`) for partition pruning on large scans.

---

## Dos and Don'ts

**Do:**

- Ask **RENT vs SALE** first — different source, key, and rules
- **RENT:** run the validated `fact_house_listing_status` + `dim_date` query
- **SALE:** count from `fact_daily_ongoing_listing` with partition filters
- Report volume at listing-key grain (`sk_house_listing` / `sk_sale_listing`)

**Don't:**

- Don't use one SQL for both contexts
- **RENT:** don't look for a materialized metrics table; don't use `house_listings_daily_info` or simplified interval checks
- **SALE:** don't reimplement status explosion ad hoc unless validating the pipeline
- Don't equate `dim_house_listing.status = 'PUBLISHED'` with the **daily historical series** — that is current state, not daily volume
- Don't count `sk_house` without understanding listing grain and dedup rules per context
