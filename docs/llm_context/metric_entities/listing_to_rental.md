# Listing to Rental (L2R)

## Overview

**Listing to Rental (L2R)** — same metric as **Listing to Contract Signed** — measures whether a **rent listing version** (`sk_house_listing`) eventually signed a rental contract.

At its core:

```
converted listing version = fact_house_listings.sk_contract <> -1
```

**How you report L2R depends on the time grain asked for** — monthly cohort rate (official corporate definition), weekly/daily cohort rates (same formula, different `DATE_TRUNC`), or windowed cuts (4W/8W). This file is the **single entry point** for all of them.

**Applies to For Rent only.** Schema and listing grain → `business_entities/house_and_listing.md`.

**Tables:** `dw_rent.dim_house_listing` (`dhl`) + `dw_rent.fact_house_listings` (`fhl`) on `sk_house_listing`. No materialized L2R metric table — run SQL.

## Related Business Entities

- House and Listing
- Closing

## Glossary and Synonyms

- **L2R**, **Listing to Rental**, **Listing2Rental**, **listing → alugado (RENT)** → **preferred names**
- **Listing to Contract Signed**, **listing_to_contract_signed**, **L2CS (listing stage)**, **conversão listing → contrato assinado** → synonyms — **same metric as L2R**
- **Days to contract**, **time to rental** → listing-level attribute `fact_house_listings.days_listing_to_contract_signed` — use for **distributions / velocity**, not as a substitute for the cohort **rate** unless combined with explicit window filters (see below)

## Scope

**Included:** all listing versions with `dhl.ts_publication IS NOT NULL` — First Listing, Re-Listing, and Recovered.

**Excluded:** listing versions without publication (`ts_publication IS NULL`).

**Cohort grain:** `sk_house_listing` (one row per rent listing version).

**Not the same as:**

- **CC2CS** (`business_entities/closing.md`) — contract created → contract signed inside the pre-contract funnel
- **Supply funnel O2L** (`metric_entities/funnel_conversions_supply.md`) — opportunity → first listing acquisition
- **L2CCV** (SALE) — see `metric_entities/listing_demand_funnel_conversions.md`

---

## Views by time grain

Pick the section that matches the question. All rates share the same join; only **cohort grouping** and **optional window filters** change.

| View | Cohort axis | Conversion window | Official? |
|------|-------------|-------------------|-----------|
| **Monthly rate** | `DATE_TRUNC('month', dhl.ts_publication)` | None — ever signed counts | ✅ **Corporate source of truth** |
| **Weekly rate** | `DATE_TRUNC('week', dhl.ts_publication)` | None — ever signed counts | Same formula, different bucket |
| **Daily rate** | `CAST(dhl.ts_publication AS DATE)` | None — ever signed counts | Same formula, different bucket |
| **Windowed rate (4W / 8W)** | Any of the above (or category slice via `listing_category_start`) | `days_listing_to_contract_signed <= 28` or `<= 56` | ⚠️ **Different metric** — label explicitly |
| **Days to contract (distribution)** | Per listing version | N/A — continuous days | Attribute, not a rate |

**Numerator (all rate views):** `COUNT(DISTINCT fhl.sk_contract)` on the validated monthly query — matches corporate SQL. For **windowed** variants, restrict to converted listings with `fhl.sk_contract <> -1` and the day window on `days_listing_to_contract_signed`.

**Denominator (all rate views):** `COUNT(DISTINCT dhl.sk_house_listing)` with `ts_publication IS NOT NULL`.

**Join:** `LEFT JOIN fact_house_listings fhl ON fhl.sk_house_listing = dhl.sk_house_listing`.

### Canonical filter (all rate views)

```sql
dhl.ts_publication IS NOT NULL
```

Add `dhl.country_code = 'BR'` (or `'MX'`) when country-specific. No `listing_category_start` filter in the **base** metric.

### Nuances

- **No maturation window** on monthly/weekly/daily ever-signed rates: a listing published in January that signs in June counts for January's cohort. Recent cohorts may look low while still converting — expected, not a data bug.
- **`listing_category_start` cohorts:** each rent version is one `sk_house_listing` row (**First Listing**, **Re-Listing**, **Recovered**). The corporate monthly rate pools all three. You can also cohort **by category** — e.g. Re-Listing-only — with the same L2R formula; filter `dhl.listing_category_start` when the question is scoped to that context.
- **Windowed 4W/8W** are optional time cuts on any scope (all categories or a single `listing_category_start`); confirm with the requester and label explicitly — not the official monthly corporate rate when windowed.
- **`days_listing_to_contract_signed`** = days from listing version start to contract signature (integer). NULL or meaningless when `sk_contract = -1`. Use for medians, percentiles, or `<= 28/56` filters — not alone as “L2R monthly”.

---

## Dos and Don'ts

**Do:**

- Route all L2R questions to this file — pick the **Views by time grain** row first
- Prefer the name **L2R** over Listing to Contract Signed in answers
- Use **`dim_house_listing` + `fact_house_listings`** — not `dim_contract` joins alone
- Report `total_listings` alongside any rate
- Label windowed or **`listing_category_start`**-sliced variants explicitly when used (e.g. Re-Listing cohort, 4W window)

**Don't:**

- Don't treat `days_listing_to_contract_signed` alone as the official monthly L2R rate
- Don't use windowed 4W/8W SQL for the corporate monthly number without saying so
- Don't confuse L2R with L2CCV (SALE), CC2CS, or supply-funnel metrics
- Don't defer to external BI — the SQL patterns below are the metric

---

## Golden Queries

### Query 1 — L2R monthly (**corporate source of truth**)

Validated corporate definition. No conversion window.

```sql
WITH sums AS (
    SELECT
        DATE_TRUNC('month', dhl.ts_publication) AS cohort_period,
        dhl.country_code,
        COUNT(DISTINCT dhl.sk_house_listing) AS total_listings,
        COUNT(DISTINCT fhl.sk_contract) AS new_contracts_signed
    FROM dw_rent.dim_house_listing AS dhl
    LEFT JOIN dw_rent.fact_house_listings AS fhl
        ON fhl.sk_house_listing = dhl.sk_house_listing
    WHERE dhl.ts_publication IS NOT NULL
    GROUP BY 1, 2
)
SELECT
    cohort_period AS month,
    country_code,
    total_listings,
    new_contracts_signed,
    CAST(new_contracts_signed AS DOUBLE) / NULLIF(total_listings, 0) AS l2r
FROM sums
ORDER BY month DESC, country_code
```

### Query 2 — L2R weekly or daily (same formula, change `DATE_TRUNC`)

Replace `cohort_period` expression only:

```sql
-- Weekly cohort
DATE_TRUNC('week', dhl.ts_publication) AS cohort_period

-- Daily cohort
CAST(dhl.ts_publication AS DATE) AS cohort_period
```

Reuse Query 1 structure; group and order by `cohort_period`.

### Query 3 — L2R with 4W / 8W window (**variant — not corporate monthly**)

Restrict numerator to listings that signed within N days of publication:

```sql
WITH base AS (
    SELECT
        DATE_TRUNC('month', dhl.ts_publication) AS cohort_period,
        dhl.country_code,
        dhl.sk_house_listing,
        fhl.sk_contract,
        fhl.days_listing_to_contract_signed
    FROM dw_rent.dim_house_listing AS dhl
    LEFT JOIN dw_rent.fact_house_listings AS fhl
        ON fhl.sk_house_listing = dhl.sk_house_listing
    WHERE dhl.ts_publication IS NOT NULL
      -- AND dhl.listing_category_start = 'First Listing'  -- or 'Re-Listing', 'Recovered'
)
SELECT
    cohort_period,
    country_code,
    COUNT(DISTINCT sk_house_listing) AS total_listings,
    COUNT(DISTINCT sk_house_listing) FILTER (
        WHERE sk_contract <> -1
          AND days_listing_to_contract_signed <= 28  -- 4W; use 56 for 8W
    ) AS listings_rented_in_window,
    1.000 * COUNT(DISTINCT sk_house_listing) FILTER (
        WHERE sk_contract <> -1
          AND days_listing_to_contract_signed <= 28
    ) / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS l2r_4w
FROM base
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

### Query 4 — Days to contract distribution (listing-level, not a rate)

```sql
SELECT
    dhl.listing_category_start,
    APPROX_PERCENTILE(fhl.days_listing_to_contract_signed, 0.5) AS median_days_to_contract,
    AVG(fhl.days_listing_to_contract_signed) AS avg_days_to_contract,
    COUNT(*) AS converted_listings
FROM dw_rent.dim_house_listing AS dhl
INNER JOIN dw_rent.fact_house_listings AS fhl
    ON fhl.sk_house_listing = dhl.sk_house_listing
WHERE dhl.country_code = 'BR'
  AND dhl.ts_publication IS NOT NULL
  AND fhl.sk_contract <> -1
GROUP BY 1
```

For demand-funnel windowed L2R via `fact_listing_rent_flows` + `dim_contract`, see `metric_entities/listing_demand_funnel_conversions.md`.
