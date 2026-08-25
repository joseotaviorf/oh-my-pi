# Listing to Unpublish (L2Unp)

## Ownership

**Data Owner:**
- bruna.prates@quintoandar.com.br

**Data Steward:**
- bruna.prates@quintoandar.com.br

## Overview

**Listing to Unpublish (L2Unp)** measures whether a **published listing version** eventually entered an **UNPUBLISHED** status interval after publication.

At its core:

```
converted listing version = at least one UNPUBLISHED interval on the listing key after publication
```

**L2Unp is a publication-cohort conversion rate**, not unpublish event volume. The denominator is listings **published** in the cohort period; the numerator is how many of those listings **unpublished** (at any time after publication, unless a window is specified).

**How you report L2Unp depends on the time grain asked for** — monthly cohort rate (default), weekly/daily cohort rates (same formula, different `DATE_TRUNC`), or windowed cuts (4W/8W). This file is the **single entry point** for all of them.

**RENT and SALE use different tables and listing keys.** Confirm context before writing SQL — see `domain_entities/house_and_listing.md`.

**Tables:** publication cohort from `dw_rent.dim_house_listing` (RENT) or `dw_sale.dim_listing` (SALE); unpublish signal from `dw_rent.fact_house_listing_status` or `dw_sale.fact_listing_status`. No materialized L2Unp metric table — run SQL.

## Related Domain Entities

- House and Listing

## Catalog

| Metric | Type |
| :---- | :---- |
| Listing to Unpublish (L2Unp) | Health Metric |

## Glossary and Synonyms

- **L2Unp**, **Listing to Unpublish**, **Listing2Unpublish**, **listing → despublicado** → **preferred names** for the **publication-cohort** definition in this file
- **Listing unpublish rate**, **taxa de despublicação (publication cohort)** → synonyms for **L2Unp** when the denominator is listings **published** in the cohort period
- **Unpublishing Rate**, **taxa de despublicação** → **generic label** — used in Owner XP / listing health **and** in other domains; **always confirm context** before SQL. The calculation depends on the question:
  - **Listing health (this file — default):** same as **L2Unp** — share of listings **published in the cohort** that eventually entered **UNPUBLISHED** after publication
  - **Unpublish event volume:** count of UNPUBLISHED **transitions** bucketed by **unpublish event date** (publication month irrelevant) — see `domain_entities/house_and_listing.md` (**Listing unpublishes**)
  - **Credit policy experiment:** share of houses unpublished within a credit-policy decision cohort on `dim_house_listing` — see `metric_entities/credit_metrics.md` (**Metric 4 — Unpublishing Rate**)
- **Despublicações / unpublish volume** → shorthand for the **event-volume** definition above (not L2Unp)

## Scope

**Included:** listing versions with a publication timestamp (`ts_publication` RENT / `ts_first_publication` SALE) that enter **`UNPUBLISHED`** after publication.

**RENT unpublish signal:** `status_history IN ('UNPUBLISHED', 'despublicado')` on `fact_house_listing_status`, with `ts_status_start >= ts_publication`.

**SALE unpublish signal:** `status_history = 'UNPUBLISHED'` on `fact_listing_status`, with `ts_status_started >= ts_first_publication`.

**Excluded:**

- `SUSPENDED`, `OPTED_OUT`, `EXCLUDED`, `EDITING` — not L2Unp unless the question explicitly asks for a different deactivation definition
- Snapshot-only status on `dim_*` without a status-history interval
- Unpublish events **before** publication on the same listing version

**Cohort grain:**

| Context | Cohort table | Publication anchor | Listing key |
|---------|--------------|-------------------|-------------|
| **RENT** | `dw_rent.dim_house_listing` | `ts_publication` | `sk_house_listing` |
| **SALE** | `dw_sale.dim_listing` | `ts_first_publication` | `sk_sale_listing` |

**Not the same as:**

- **Unpublish volume** — event count by unpublish month/week/day (`house_and_listing.md`, **Listing unpublishes**)
- **Credit Unpublishing Rate** — `metric_entities/credit_metrics.md`
- **L2R** — publication cohort to signed contract (`metric_entities/listing_to_rental.md`)

---

## Calculation

Every rate view is the same ratio, evaluated per **publication** cohort:

```
L2Unp (cohort) = COUNT(DISTINCT listings with UNPUBLISHED after publication)
                 / COUNT(DISTINCT listings published in cohort)
```

### Answering “Qual é o L2Unp do mês passado?”

**Disambiguate the cohort first** — “mês passado” is ambiguous:

| User intent | Cohort axis | Metric |
|-------------|-------------|--------|
| Listings **published** last month — how many of those eventually unpublished? | `DATE_TRUNC('month', ts_publication)` / `ts_first_publication` | **L2Unp** (this file) |
| Listings that **unpublished** last month — regardless of when they were published | `DATE_TRUNC('month', ts_status_start)` / `ts_status_started` on the UNPUBLISHED interval | **Unpublish volume** — `house_and_listing.md` (**Listing unpublishes**) |

If the question does not specify, **ask** which row applies — or state the assumption explicitly in the answer.

1. **Confirm RENT vs SALE** — if unspecified, ask or state the assumption used (many Owner XP / listing-health cuts are **RENT / BR**).
2. **Default L2Unp reading:** “mês passado” = **publication cohort** of the previous calendar month — listings whose `ts_publication` (RENT) or `ts_first_publication` (SALE) falls in that month. A listing published in that month that unpublishes later still counts in that cohort's numerator.
3. **Not L2Unp:** unpublish **events** that occurred last month on listings published in an earlier month — that is **unpublish volume** (event-date bucket).
4. Report **`total_listings`** (denominator) and **`listings_unpublished`** (numerator) alongside the rate.
5. **No maturation window** on the default monthly rate — a listing published in January that unpublishes in June counts for January's cohort (same pattern as L2R).

### Views by time grain

| View | Cohort axis | Conversion window | Official? |
|------|-------------|-------------------|-----------|
| **Monthly rate** | `DATE_TRUNC('month', publication_ts)` | None — ever unpublished after publication counts | ✅ **Default** |
| **Weekly rate** | `DATE_TRUNC('week', publication_ts)` | None — ever unpublished counts | Same formula, different bucket |
| **Daily rate** | `CAST(publication_ts AS DATE)` | None — ever unpublished counts | Same formula, different bucket |
| **Windowed rate (4W / 8W)** | Any cohort axis above | Unpublish within 28 / 56 days of publication | ⚠️ **Different metric** — label explicitly |

**Numerator (all rate views):** `COUNT(DISTINCT listing_key)` with at least one qualifying UNPUBLISHED interval after publication (and within the window when windowed).

**Denominator (all rate views):** `COUNT(DISTINCT listing_key)` with publication timestamp not null.

### Canonical filter (all rate views)

**RENT:**

```sql
dhl.ts_publication IS NOT NULL
-- AND dhl.country_code = 'BR'
```

**SALE:**

```sql
dl.ts_first_publication IS NOT NULL
-- join dim_region for country_code when country-specific
```

No `listing_category_start` filter in the **base** metric (RENT pools First Listing, Re-Listing, and Recovered).

### Nuances

- **Incomplete cohorts:** recent publication months may still accumulate unpublishes — rates can rise over time; state when the cohort is still open (same as L2R / demand-funnel metrics).
- **`listing_category_start` cohorts (RENT):** slice with `dhl.listing_category_start` when the question is scoped (e.g. Re-Listing-only).
- **Republication within 12 weeks (RENT):** reuses the same `sk_house_listing` — unpublish on that version still counts for that version's publication cohort.
- **Hybrid houses:** compute RENT and SALE separately; do not dedupe on `sk_house` without an explicit rule.
- **Reason breakdown:** for **1P owner deactivation** use `deactivation_*` when populated; otherwise `status_change_reason` — see `house_and_listing.md` (**Status reasons — which column to use**). Not required for the headline L2Unp rate.
- **Owner XP / Superset experiment dashboards** may reuse this definition — route here instead of treating L2Unp as undefined.

---

## Dos and Don'ts

**Do:**

- Route all **L2Unp** / **listing unpublish rate by publication cohort** questions to this file
- Use **publication date** for the cohort axis — not unpublish event date
- Use **status history facts** (`fact_house_listing_status` / `fact_listing_status`) — not `dim_* .status` snapshot alone
- Report cohort size with the rate
- Label windowed or category-sliced variants explicitly

**Don't:**

- Don't answer “L2Unp do mês passado” with unpublish **volume** bucketed by `ts_status_start` — confirm whether the user meant **publication cohort** (L2Unp) or **unpublish event month** (`house_and_listing.md`, **Listing unpublishes**)
- Don't treat **Unpublishing Rate** as always L2Unp — credit-policy and event-volume definitions use different numerators, denominators, and tables
- Don't count `OPTED_OUT` or `SUSPENDED` as L2Unp unless the question explicitly asks for those statuses
- Don't use **Credit Unpublishing Rate** SQL for listing-health L2Unp
- Don't COALESCE `deactivation_reason` with `status_change_reason` — pick per row per `house_and_listing.md` (**Status reasons — which column to use**)
- Don't defer to DataHub/Superset experiment artifacts as “no official definition” — run the golden query below

---

## Golden Queries

### Query 1 — L2Unp monthly, RENT (**default pattern**)

Includes filter for **last month's publication cohort** — adapt `cohort_period` as needed.

```sql
WITH sums AS (
    SELECT
        DATE_TRUNC('month', dhl.ts_publication) AS cohort_period,
        dhl.country_code,
        COUNT(DISTINCT dhl.sk_house_listing) AS total_listings,
        COUNT(DISTINCT CASE
            WHEN fhls.sk_house_listing IS NOT NULL THEN dhl.sk_house_listing
        END) AS listings_unpublished
    FROM dw_rent.dim_house_listing AS dhl
    LEFT JOIN dw_rent.fact_house_listing_status AS fhls
        ON fhls.sk_house_listing = dhl.sk_house_listing
       AND fhls.country_code = dhl.country_code
       AND fhls.status_history IN ('UNPUBLISHED', 'despublicado')
       AND fhls.ts_status_start >= dhl.ts_publication
    WHERE dhl.ts_publication IS NOT NULL
    GROUP BY 1, 2
)
SELECT
    cohort_period AS month,
    country_code,
    total_listings,
    listings_unpublished,
    CAST(listings_unpublished AS DOUBLE) / NULLIF(total_listings, 0) AS l2unp
FROM sums
WHERE cohort_period = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1' MONTH
ORDER BY country_code
```

### Query 2 — L2Unp monthly, SALE

```sql
WITH sums AS (
    SELECT
        DATE_TRUNC('month', dl.ts_first_publication) AS cohort_period,
        dr.country_code,
        COUNT(DISTINCT dl.sk_sale_listing) AS total_listings,
        COUNT(DISTINCT CASE
            WHEN fls.sk_sale_listing IS NOT NULL THEN dl.sk_sale_listing
        END) AS listings_unpublished
    FROM dw_sale.dim_listing AS dl
    INNER JOIN dw_house.dim_house AS dh
        ON dl.sk_house = dh.sk_house
    INNER JOIN dw_public.dim_region AS dr
        ON dh.sk_region = dr.sk_region
    LEFT JOIN dw_sale.fact_listing_status AS fls
        ON fls.sk_sale_listing = dl.sk_sale_listing
       AND fls.status_history = 'UNPUBLISHED'
       AND fls.ts_status_started >= dl.ts_first_publication
    WHERE dl.ts_first_publication IS NOT NULL
    GROUP BY 1, 2
)
SELECT
    cohort_period AS month,
    country_code,
    total_listings,
    listings_unpublished,
    CAST(listings_unpublished AS DOUBLE) / NULLIF(total_listings, 0) AS l2unp
FROM sums
WHERE cohort_period = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1' MONTH
ORDER BY country_code
```

### Query 3 — L2Unp with 4W window (**variant — not default monthly**)

RENT example — restrict unpublish to within 28 days of publication:

```sql
WITH base AS (
    SELECT
        DATE_TRUNC('month', dhl.ts_publication) AS cohort_period,
        dhl.country_code,
        dhl.sk_house_listing,
        MAX(CASE
            WHEN fhls.status_history IN ('UNPUBLISHED', 'despublicado')
             AND fhls.ts_status_start >= dhl.ts_publication
             AND fhls.ts_status_start <= dhl.ts_publication + INTERVAL '28' DAY
            THEN 1 ELSE 0
        END) AS is_unpublished_4w
    FROM dw_rent.dim_house_listing AS dhl
    LEFT JOIN dw_rent.fact_house_listing_status AS fhls
        ON fhls.sk_house_listing = dhl.sk_house_listing
       AND fhls.country_code = dhl.country_code
    WHERE dhl.ts_publication IS NOT NULL
    GROUP BY 1, 2, 3
)
SELECT
    cohort_period,
    country_code,
    COUNT(DISTINCT sk_house_listing) AS total_listings,
    COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_unpublished_4w = 1) AS listings_unpublished_4w,
    1.000 * COUNT(DISTINCT sk_house_listing) FILTER (WHERE is_unpublished_4w = 1)
        / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS l2unp_4w
FROM base
GROUP BY 1, 2
ORDER BY 1 DESC, 2
```

For unpublish **volume** by event date (not L2Unp), see golden queries 6–8 in `domain_entities/house_and_listing.md`.
