# Supply Retention (Sale)

## Overview

**Supply Retention (Sale)** measures, month over month, the flow of published Sale (For Sale) listing inventory on QuintoAndar: how many listings were published for the first time (**FL**), how many returned to `PUBLISHED` after having left (**Republished**), how many left (**Churn**), how many converted to a signed contract (**CCV**), and what the published stock was at the start and end of each month.

The naive way to compute this — diffing month-over-month counts — does not work, because it cannot see status changes that happen _inside_ the month (a listing that publishes and unpublishes within the same month would simply disappear from both counts). Supply Retention instead reconstructs a **point-in-time snapshot** of each listing's status at a fixed cutoff (23:59:59 UTC of the last day of the month, or "now" UTC for the current, still-open month) and classifies transitions between two consecutive snapshots. A listing that publishes and unpublishes inside the same month ("flicker") is deliberately counted as **both** a FL and a Churn, so the stock identity below still closes exactly.

**Exists exclusively for the Sale (Venda) vertical.** The query is built entirely from `dw_sale.*` fact tables and fixes `business_context = 'SALE'` in its output; there is no equivalent For Rent instance of this metric today.

**Important — local redefinitions, not the corporate metrics of the same name:** the **FL**, **OL**, **Republished**, **Churn** and **CCV** components documented here are calculated specifically for Supply Retention (Sale) and diverge from the corporate Data Products of similar names already registered in DataHub:

| Component | This document (Supply Retention) | Corporate DataHub metric |
| --- | --- | --- |
| FL | No `city_group` restriction; 1P/3P via `obt_supply.planning_operation` | `first-listings-1p` — restricted to 8 focus `city_group`s; 1P/3P via `dw_sale.dim_listing.is_3p_supply` |
| OL | Monthly (or weekly) end-of-period snapshot from `dw_sale.fact_listing_status` | `ongoing-listings` — daily grain from the materialized table `dw_sale.fact_daily_ongoing_listing` |
| CCV | Business conversion count, `CCV_SIGNED` scoped to this snapshot logic | The `L2CCV` step of `listing-demand-funnel-conversions` measures a different thing (demand funnel to conversion, not supply status flow) |

**Use the definitions in this document only when the question is specifically about Supply Retention.** For general questions about the corporate FL or Ongoing Listings metrics, use their own DataHub entries (`first-listings-1p`, `ongoing-listings`) instead — do not mix the two.

## Related Business Entities

*   House and Listing
    

## Glossary and Synonyms

*   **Supply Retention**, **Supply Retention (Sale)**, **Retenção de Estoque (Venda)** → this metric
    
*   **FL**, **First Listing** (in the Supply Retention context only) → component: first-ever publication of a listing, this month
    
*   **OL**, **Ongoing Listing** (in the Supply Retention context only) → component: `PUBLISHED` at the end-of-month/end-of-week snapshot
    
*   **Republished** → component: re-entered `PUBLISHED` this month, not a first listing
    
*   **Churn** → component: left `PUBLISHED` this month without converting (or "flickered" without converting)
    
*   **CCV** → component: signed sale contract (`CCV_SIGNED`) this month — the business conversion metric
    
*   **CCV_exit** → reconciliation-only subset of Churn/flicker that converted this month; never the business conversion number (that is **CCV**)
    

## Scope

**Included**: Sale listings only (`business_context` fixed to `'SALE'` in the output), sourced from `dw_sale.fact_listing_status`; both **1P** and **3P** operation, all city groups (no `city_group` filter — unlike the corporate FL/OL metrics). Standard monthly window: last 6 closed months + current month (partial, cut "now" UTC). Weekly extension: last 5 closed ISO weeks (Monday–Sunday) + current partial week.

**Excluded**: For Rent listings entirely (this document has no Rent equivalent). Any CCV volume comparison against 2025 months **before November** is unreliable — `status_closing_history = 'CCV_SIGNED'` is very poorly populated before Nov/2025 (15–57 rows/month vs. 1,100+ rows/month from Nov/2025 on); this is a source-data coverage gap, not a query defect. In the price-bucket extension, listings without a price (0.08%, 1,293 of 1.67M) fall into a `(no price)` bucket rather than being dropped.

## Calculation

The correct calculation reconstructs, for each month (or week), whether each listing was `PUBLISHED` at a fixed cutoff instant, then classifies transitions between consecutive snapshots — rather than looking at status changes throughout the month.

The stock identity closes by construction, per `city_group` / `operation`, month over month:


```
markup
opening_stock + FL + Republished − Churn − CCV_exit = closing_stock
```


where:

*   **opening_stock / closing_stock** = count of listings `PUBLISHED` at the end-of-previous-month and end-of-current-month snapshots, respectively.
    
*   **FL** = `COUNT(DISTINCT sk_sale_listing)` whose lifetime-first publication (`sk_first_publication_date`, resolved via `dim_date`) falls in this month. A listing that publishes and unpublishes within the same month still counts as FL even though it never appears `PUBLISHED` in either snapshot.
    
*   **Republished** = entered `PUBLISHED` this month (vs. the previous month's snapshot) **minus** whoever is FL this month — otherwise a listing's lifetime-first publication would double-count as both FL and Republished.
    
*   **Churn** = left `PUBLISHED` this month (was `PUBLISHED` in the previous snapshot, isn't in this one) **and did not convert** this month, **union** the "flicker" case: FL this month but never appeared `PUBLISHED` in either snapshot, and did not convert.
    
*   **CCV** = every listing with `CCV_SIGNED` whose `ts_status_started` falls in this month — the business conversion metric, independent of what happens to publication status afterward.
    
*   **CCV_exit** = reconciliation-only subset of Churn/flicker that _did_ convert this month (`CCV_exit ≤ CCV`, since CCV also includes conversions that stay `PUBLISHED`, ~8% of cases). Exists purely to make the stock identity above balance; the business conversion number is always **CCV**, never CCV_exit.
    
*   **reconciliation_diff** = `closing_stock_actual − closing_stock_calculated` (the formula above). A validation column, not a business metric — validated at ~100% zero, with isolated ±1 residuals in~ 0.001% of rows (unexplained after investigation; treated as isolated data noise, not a logic failure).
    

**Known accepted limitation:** a listing that converts (CCV signed) in month M but only actually leaves `PUBLISHED` in a later month is counted as ordinary Churn in the month it leaves, not as a delayed conversion — the conversion exclusion is scoped to the month the CCV occurred, not carried forward. Measured via Trino: 648 listings affected, of which 333 land in regular Churn instead of CCV_exit. This is an accepted design limitation (month-scoped exclusion), not something to fix.

### Canonical Filter

Apply on `dw_sale.fact_listing_status` (joined to `dw_growth.obt_supply` for 1P/3P classification, `dw_public.dim_region` and `dw_public.dim_date`):


```sql
-- business_context is always the fixed constant 'SALE' in the output — never read
-- directly from obt_supply.nm_business_context.
-- sk_first_publication_date <> -1 excludes the sentinel "no date" value.
f.sk_first_publication_date <> -1

-- 1P/3P classification (operation): a house (sk_house) is 3P if ANY of its rows
-- in obt_supply has planning_operation = 'Rede', filtered to nm_business_context = 'SALE'.
```


**Warning**: skipping the `nm_business_context = 'SALE'` filter when building the 1P/3P classification from `obt_supply` misclassifies ~340 of 1.65 million houses, because the same house can carry a different operation classification under the RENT context. Likewise, reading `business_context` straight from `obt_supply.nm_business_context` instead of fixing it to `'SALE'` in the output is wrong: 179,000 houses that appear in `fact_listing_status` also have RENT history in `obt_supply`.

### Nuances

This metric has no weight/parameter table — it is fully derived from status logic — but two non-obvious parsing/timing patterns are mandatory:

| Pattern | Rule |
| --- | --- |
| Snapshot cutoff comparison | `ts_status_started` / `ts_status_ended` are `TIMESTAMP WITH TIME ZONE` (stored UTC). Comparing them directly against a "naive" cutoff timestamp makes Trino reinterpret the comparison using the session timezone (`America/Sao_Paulo`, UTC-3), shifting the month boundary by 3 hours. Always `CAST(... AS TIMESTAMP)` explicitly on both sides. |
| CCV date field | Use `ts_status_started` (when the signature happened), never `ts_status_ended` / `sk_status_end_date` — ~49% of `CCV_SIGNED` rows have their end pointing at a sentinel key (status still "open"), which undercounts CCV by 8–10x if measured off the end date. Also `CAST` is required here too: without it, `date_trunc('month', TIMESTAMP WITH TIME ZONE)` returns a `TIMESTAMP WITH TIME ZONE` that never equals the `DATE` month boundary, silently zeroing `is_ccv`. |

**Join keys**: `sk_house = FLOOR(sk_sale_listing / 1000)` links a listing to its house in `obt_supply`. `fact_listings.sk_sale_listing = f.sk_sale_listing` for the price-bucket grain. `dim_company_3p_partners.sk_company` for the churn-by-broker extension.

**Fallback**: none applicable — there is no parameter table or missing-period fallback logic in this metric.

## Dos and Don'ts

**Do:**

*   Reconstruct status with `CAST(ts_status_started AS TIMESTAMP) <= cutoff AND (ts_status_ended IS NULL OR CAST(ts_status_ended AS TIMESTAMP) > cutoff)` — do not use the day-granularity keys `sk_status_start_date` / `sk_status_end_date`, which hide same-day status transitions (this previously produced a spurious "overlap" on 1,673 listings).
    
*   Use `ts_status_started` for the CCV date, never the end date.
    
*   Apply the `nm_business_context = 'SALE'` filter inside the 1P/3P house classification.
    
*   Treat CCV volume before Nov/2025 as unreliable due to source coverage, not as a query bug.
    

**Don't:**

*   Don't read `business_context` from `obt_supply.nm_business_context` — always fix it to `'SALE'` in the output.
    
*   Don't compare `TIMESTAMP WITH TIME ZONE` columns directly against a naive timestamp without an explicit `CAST` — Trino silently reinterprets using the session timezone.
    
*   Don't exclude converted-but-still-`PUBLISHED` listings from OL — OL counts them by design (~8% of cases); the indicator tracks published stock, not completed sales.
    
*   Don't reuse this document's FL/OL/Churn definitions for questions about the corporate "FL (First Listings)" or "Ongoing Listings (Daily Volume)" Data Products — different scope and classification logic.
    

## Golden Queries

Base query computing FL, OL, Republished, Churn, CCV, CCV_exit and the stock reconciliation, monthly, by `city_group` × `operation`, for the current 6 closed months + current partial month, plus the same 4 months one year prior for YoY comparison. This snapshot-reconstruction and 1P/3P classification pattern is exclusive to Supply Retention — it is not shared with an existing component CTE in the House and Listing business entity, which documents the underlying raw tables but not this specific reconciliation pattern.


```sql
WITH
-- "current" period: n=0 is the current (partial, "as of now") month; n=1..6 are
-- the last 6 closed months; n=7 exists only to provide the "previous month" for
-- n=6 in the snapshot_pairs self-join.
-- "last_year" period: the same months one year back — n=0..3 (all closed); n=4
-- exists only to provide the "previous month" for n=3.
month_defs AS (
    SELECT
        'current' AS period,
        n,
        date_trunc('month', date_add('month', -n, current_date)) AS month_start,
        CASE
            WHEN n = 0 THEN CAST(current_timestamp AT TIME ZONE 'UTC' AS TIMESTAMP)
            ELSE CAST(date_trunc('month', date_add('month', -n, current_date)) AS TIMESTAMP)
                     + INTERVAL '1' month - INTERVAL '1' second
        END AS snapshot_cutoff_ts
    FROM UNNEST(sequence(0, 7)) AS t(n)
    UNION ALL
    SELECT
        'last_year' AS period,
        n,
        date_add('year', -1, date_trunc('month', date_add('month', -n, current_date))) AS month_start,
        CAST(date_add('year', -1, date_trunc('month', date_add('month', -n, current_date))) AS TIMESTAMP)
            + INTERVAL '1' month - INTERVAL '1' second AS snapshot_cutoff_ts
    FROM UNNEST(sequence(0, 4)) AS t(n)
),
-- 1P/3P classification (operation) per sk_house. Filters nm_business_context = 'SALE':
-- without it, houses that were only planning_operation = 'Rede' under RENT (not SALE)
-- would be misclassified as 3P even for sale metrics.
house_supply_classification AS (
    SELECT
        sk_house,
        MAX(CASE WHEN planning_operation = 'Rede' THEN 1 ELSE 0 END) AS is_3p
    FROM dw_growth.obt_supply
    WHERE nm_business_context = 'SALE'
    GROUP BY sk_house
),
-- Single scan of fact_listing_status, already carrying real dates, city_group and
-- operation (1P/3P). ts_status_started/ts_status_ended are the table's own real
-- timestamps, with no sentinel and no need to join dim_date. sk_first_publication_date
-- still goes through dim_date (no equivalent timestamp exists on the table).
fact_enriched AS (
    SELECT
        f.sk_sale_listing,
        f.status_history,
        f.status_closing_history,
        f.sk_first_publication_date,
        d_fpd.date   AS first_publication_date,
        f.ts_status_started,
        f.ts_status_ended,
        r.city_group,
        CASE WHEN hc.is_3p = 1 THEN '3P' ELSE '1P' END AS operation
    FROM dw_sale.fact_listing_status f
    LEFT JOIN dw_public.dim_date d_fpd
        ON f.sk_first_publication_date = d_fpd.sk_date
       AND f.sk_first_publication_date <> -1
    LEFT JOIN dw_public.dim_region r
        ON f.sk_region = r.sk_region
    LEFT JOIN house_supply_classification hc
        ON hc.sk_house = CAST(f.sk_sale_listing / 1000 AS BIGINT)
),
-- fact_enriched x 8 snapshots (partial current month + 7 end-of-month snapshots),
-- with FL / status-at-snapshot / CCV flags.
base AS (
    SELECT
        fe.sk_sale_listing,
        fe.city_group,
        fe.operation,
        m.period,
        m.n,
        -- "Active at snapshot" = active at the cutoff instant of each month (23:59:59
        -- UTC of the last day, or "now" UTC for the current month). The explicit
        -- CAST(...AS TIMESTAMP) on ts_status_started/ended is mandatory: comparing a
        -- TIMESTAMP WITH TIME ZONE directly against a naive timestamp makes Trino
        -- reinterpret the comparison using the session timezone (America/Sao_Paulo,
        -- UTC-3), shifting the boundary by 3h.
        CASE
            WHEN CAST(fe.ts_status_started AS TIMESTAMP) <= m.snapshot_cutoff_ts
             AND (fe.ts_status_ended IS NULL
                  OR CAST(fe.ts_status_ended AS TIMESTAMP) > m.snapshot_cutoff_ts)
            THEN fe.status_history
        END AS status_at_snapshot,
        CASE
            WHEN fe.sk_first_publication_date <> -1
             AND date_trunc('month', fe.first_publication_date) = m.month_start
            THEN 1 ELSE 0
        END AS is_fl,
        -- CCV: month of ts_status_started (when the signature happened), not
        -- sk_status_end_date and not sk_status_start_date. The CAST here is also
        -- mandatory: without it, date_trunc('month', TIMESTAMP WITH TIME ZONE)
        -- returns a TIMESTAMP WITH TIME ZONE that never equals m.month_start (DATE)
        -- in Trino — is_ccv would silently stay 0.
        CASE
            WHEN fe.status_closing_history = 'CCV_SIGNED'
             AND date_trunc('month', CAST(fe.ts_status_started AS TIMESTAMP)) = CAST(m.month_start AS TIMESTAMP)
            THEN 1 ELSE 0
        END AS is_ccv
    FROM fact_enriched fe
    CROSS JOIN month_defs m
),
-- FL, OL and CCV in a single GROUP BY (same column inside every COUNT DISTINCT,
-- only the CASE condition changes — avoids stage explosion).
agg_direct AS (
    SELECT
        period,
        n,
        city_group,
        operation,
        COUNT(DISTINCT CASE WHEN is_fl = 1 THEN sk_sale_listing END) AS fl_count,
        COUNT(DISTINCT CASE WHEN status_at_snapshot = 'PUBLISHED' THEN sk_sale_listing END) AS ol_count,
        COUNT(DISTINCT CASE WHEN is_ccv = 1 THEN sk_sale_listing END) AS ccv_count
    FROM base
    GROUP BY 1, 2, 3, 4
),
-- Status per listing/month, already collapsed to one row per sk_sale_listing,
-- period, n.
status_by_month AS (
    SELECT
        sk_sale_listing,
        city_group,
        operation,
        period,
        n,
        -- The original overlap (1,673 listings with 2+ "active" statuses in the same
        -- snapshot) was already fixed at the root in `base`, by using
        -- ts_status_started/ts_status_ended with an end-of-day cutoff instead of
        -- sk_status_start/end_date (day granularity). The "overlap" was, in practice,
        -- a status transition happening within the same calendar day — not a genuine
        -- ambiguity. This COALESCE remains only as a safety net for genuine timestamp
        -- overlaps (corrupted data); it should no longer fire under normal conditions.
        COALESCE(
            MAX(CASE WHEN status_at_snapshot = 'PUBLISHED' THEN status_at_snapshot END),
            MAX(status_at_snapshot)
        ) AS status_at_snapshot
    FROM base
    WHERE status_at_snapshot IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5
),
-- Conversion flag per listing/period/month, reusing is_ccv (does not depend on
-- status_at_snapshot being non-null: the CCV can have occurred on a row that was
-- already superseded by another before month-end).
conversion_by_month AS (
    SELECT
        sk_sale_listing,
        period,
        n,
        MAX(is_ccv) AS is_converted_this_month
    FROM base
    GROUP BY 1, 2, 3
),
-- FL flag per listing/period/month (reuses is_fl from base). Used only to prevent
-- Republished from counting the same listing that is already in FL — see
-- retention_flags.
fl_by_month AS (
    SELECT
        sk_sale_listing,
        period,
        n,
        MAX(is_fl) AS is_fl
    FROM base
    GROUP BY 1, 2, 3
),
-- Current month (n) x previous month (n+1) pair — the only self-join needed. The
-- join matches prev.period = cur.period: without it, a listing's "previous month"
-- in the "current" period could incorrectly come from the "last_year" period (or
-- vice-versa) purely because the n values match.
snapshot_pairs AS (
    SELECT
        COALESCE(cur.period, prev.period) AS period,
        COALESCE(cur.n, prev.n - 1) AS n_current,
        COALESCE(cur.city_group, prev.city_group) AS city_group,
        COALESCE(cur.operation, prev.operation) AS operation,
        COALESCE(cur.sk_sale_listing, prev.sk_sale_listing) AS sk_sale_listing,
        cur.status_at_snapshot  AS status_current,
        prev.status_at_snapshot AS status_previous
    FROM status_by_month cur
    FULL OUTER JOIN status_by_month prev
        ON prev.sk_sale_listing = cur.sk_sale_listing
       AND prev.period = cur.period
       AND prev.n = cur.n + 1
),
-- Republished and Churn/CCV_exit are now STRICT PARTITIONS of groups C (entered
-- PUBLISHED this snapshot) and B (left PUBLISHED this snapshot), defined only by
-- the two consecutive snapshots. This is what makes
-- opening_stock + FL + Republished - Churn - CCV_exit = closing_stock close by
-- construction, even without looking at what happened mid-month:
--   Entries (C) = FL (lifetime-first publication) + Republished (rest of C)
--   Exits   (B) = CCV_exit (left PUBLISHED via CCV_SIGNED this month)
--                 + Churn (rest of B)
retention_flags AS (
    SELECT
        sp.period,
        sp.n_current AS n,
        sp.city_group,
        sp.operation,
        -- Opening/closing stock (same snapshot feeding OL in agg_direct — used only
        -- for the reconciliation below).
        COUNT(DISTINCT CASE WHEN sp.status_previous = 'PUBLISHED' THEN sp.sk_sale_listing END) AS opening_stock_count,
        COUNT(DISTINCT CASE WHEN sp.status_current  = 'PUBLISHED' THEN sp.sk_sale_listing END) AS closing_stock_count,
        -- Republished = C MINUS whoever is FL this month. Without this "minus", a
        -- listing's lifetime-first publication would be counted in FL and in
        -- Republished at the same time.
        COUNT(DISTINCT CASE
            WHEN COALESCE(sp.status_previous, 'NOT_PUBLISHED') <> 'PUBLISHED'
             AND sp.status_current = 'PUBLISHED'
             AND COALESCE(flm.is_fl, 0) = 0
            THEN sp.sk_sale_listing END) AS republished_count,
        -- Churn = B (left PUBLISHED via snapshot) MINUS converters, UNION the FL
        -- "flicker": a listing published for the first time this month
        -- (flm.is_fl=1) but never appeared PUBLISHED in either snapshot (never
        -- entered C). The two branches of the CASE are mutually exclusive by
        -- construction: flm.is_fl=1 implies status_previous <> 'PUBLISHED' (it
        -- cannot have been published before its own first publication), so it
        -- never fires together with branch B (which requires
        -- status_previous = 'PUBLISHED').
        COUNT(DISTINCT CASE
            WHEN sp.status_previous = 'PUBLISHED'
             AND COALESCE(sp.status_current, 'NOT_PUBLISHED') <> 'PUBLISHED'
             AND COALESCE(cm.is_converted_this_month, 0) = 0
            THEN sp.sk_sale_listing
            WHEN COALESCE(flm.is_fl, 0) = 1
             AND NOT (COALESCE(sp.status_previous, 'NOT_PUBLISHED') <> 'PUBLISHED'
                      AND sp.status_current = 'PUBLISHED')
             AND COALESCE(cm.is_converted_this_month, 0) = 0
            THEN sp.sk_sale_listing
        END) AS churn_count,
        -- CCV_exit = subset of B that converted this month, UNION the same FL
        -- flicker above when the listing converted (CCV_SIGNED) within its own
        -- first-publication month. Always LESS THAN OR EQUAL TO agg_direct's "ccv"
        -- (which counts every signature in the month, including those that stayed
        -- PUBLISHED afterward) — ccv_exit exists only for the stock reconciliation;
        -- the business "ccv" metric remains the one in agg_direct.
        COUNT(DISTINCT CASE
            WHEN sp.status_previous = 'PUBLISHED'
             AND COALESCE(sp.status_current, 'NOT_PUBLISHED') <> 'PUBLISHED'
             AND COALESCE(cm.is_converted_this_month, 0) = 1
            THEN sp.sk_sale_listing
            WHEN COALESCE(flm.is_fl, 0) = 1
             AND NOT (COALESCE(sp.status_previous, 'NOT_PUBLISHED') <> 'PUBLISHED'
                      AND sp.status_current = 'PUBLISHED')
             AND COALESCE(cm.is_converted_this_month, 0) = 1
            THEN sp.sk_sale_listing
        END) AS ccv_exit_count
    FROM snapshot_pairs sp
    LEFT JOIN conversion_by_month cm
        ON cm.sk_sale_listing = sp.sk_sale_listing
       AND cm.period = sp.period
       AND cm.n = sp.n_current
    LEFT JOIN fl_by_month flm
        ON flm.sk_sale_listing = sp.sk_sale_listing
       AND flm.period = sp.period
       AND flm.n = sp.n_current
    -- Filter by period: "current" reports n=0..6 (6 closed months + current
    -- month); "last_year" reports n=0..3 (the same 4 months one year back). n=7/
    -- n=4 (each period's "previous month") only feed the self-join above and
    -- never appear in the result.
    WHERE (sp.period = 'current'   AND sp.n_current BETWEEN 0 AND 6)
       OR (sp.period = 'last_year' AND sp.n_current BETWEEN 0 AND 3)
    GROUP BY 1, 2, 3, 4
),
all_keys AS (
    SELECT period, n, city_group, operation FROM agg_direct
    WHERE (period = 'current' AND n BETWEEN 0 AND 6)
       OR (period = 'last_year' AND n BETWEEN 0 AND 3)
    UNION
    SELECT period, n, city_group, operation FROM retention_flags
)
SELECT
    md.month_start,
    ak.city_group,
    'SALE' AS business_context,
    ak.operation,
    COALESCE(ad.ol_count, 0)          AS ol,
    COALESCE(ad.fl_count, 0)          AS fl,
    COALESCE(rf.republished_count, 0) AS republished,
    COALESCE(rf.churn_count, 0)       AS churn,
    COALESCE(ad.ccv_count, 0)         AS ccv,
    -- Stock reconciliation (validation, not a business metric):
    -- opening_stock + fl + republished - churn - ccv_exit must match
    -- closing_stock_actual. Churn/CCV_exit already include the FL "flicker", so
    -- "fl" (business metric) goes directly into the formula. For n=0 (current,
    -- partial month) the identity still holds, except "closing_stock_actual"
    -- reflects the stock AS OF NOW (not a formal month close).
    COALESCE(rf.opening_stock_count, 0)  AS opening_stock,
    COALESCE(rf.closing_stock_count, 0)  AS closing_stock_actual,
    COALESCE(rf.ccv_exit_count, 0)       AS ccv_exit,
    COALESCE(ad.fl_count, 0) + COALESCE(rf.republished_count, 0)
        + COALESCE(rf.opening_stock_count, 0)
        - COALESCE(rf.churn_count, 0) - COALESCE(rf.ccv_exit_count, 0) AS closing_stock_calculated,
    COALESCE(rf.closing_stock_count, 0) -
      (COALESCE(ad.fl_count, 0) + COALESCE(rf.republished_count, 0)
        + COALESCE(rf.opening_stock_count, 0)
        - COALESCE(rf.churn_count, 0) - COALESCE(rf.ccv_exit_count, 0)) AS reconciliation_diff
FROM all_keys ak
JOIN month_defs md
    ON md.period = ak.period AND md.n = ak.n
LEFT JOIN agg_direct ad
    ON ad.period = ak.period AND ad.n = ak.n AND ad.city_group = ak.city_group AND ad.operation = ak.operation
LEFT JOIN retention_flags rf
    ON rf.period = ak.period AND rf.n = ak.n AND rf.city_group = ak.city_group AND rf.operation = ak.operation
ORDER BY md.month_start, ak.city_group, ak.operation;
```


**Documented extensions built on top of this base query** (not restated here as separate golden queries; same core logic, different grain or slice):

*   **Price bucket** — adds `price_bucket` (`0-1M` / `1-3M` / `+3M` / `(no price)`) via a join to `dw_sale.fact_listings.price` on `sk_sale_listing`. `fact_listings` holds a **static** price per listing (no monthly price history), so a listing's bucket is the same across every monthly snapshot it appears in — it does not necessarily reflect the price "at the time."
    
*   **Weekly grain** — same logic, replacing the end-of-month snapshot with an end-of-ISO-week snapshot (`date_trunc('week', ...)`, Monday–Sunday). Default window: last 5 closed weeks + current partial week.
    
*   **Churn by 3P broker** — a derived query restricted to `operation = '3P'` that attributes each Churn event to the broker (`sk_company → dim_company_3p_partners.hubspot_company_tag`) holding the listing published in the previous month (or the current snapshot's broker, for the FL-flicker case, where there is no true "previous broker"). `hubspot_company_tag` coverage: ~99.25% of 3P rows; the remainder falls into `(no tag / unidentified)`. Monthly Churn totals from this query match exactly the `operation = '3P'` Churn totals from the main query.

## DataHub catalog

- **Data Product:** `urn:li:dataProduct:supply-retention-sale`

