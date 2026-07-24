# ER2RR (ERC to Re-Rent Rate — 4w / 8w / 12w)

## Ownership

**Data Owner:**
- flavia.rocha@quintoandar.com.br

**Data Steward:**
- flavia.rocha@quintoandar.com.br

## Overview

**ER2RR** (Ended Rental to Re-Rental) is the conversion rate of ended rentals into a
new rental contract within a fixed post-termination window. The cohort starts at
**ERC (Ended Rental Confirmed)** — the exit inspection date that marks a rental as
effectively terminated — and the metric measures what share of that ERC cohort has a
next contract (`sk_next_contract`) signed by a given number of weeks after ERC. It
can be reported at **monthly or weekly cadence** — same definition and same shared-
cohort logic either way, only the calendar grouping granularity changes (see Cohort
window definition for monthly, Weekly cohort window definition for weekly).

**Exists exclusively for For Rent Brazil.** (Confirmed with the Data Steward —
consistent with the `country_code != 'MX'` canonical filter below, which already
excludes the only other country FR operates in.)

**ER2RR is reported in three look-forward horizons — 4w, 8w, 12w (28 / 56 / 84
days)** — but **all three share the exact same cohort population** (same
denominator, same ERC month-grouping, defined by the 4w/28-day maturation window —
see Cohort window definition). They are **not** three independently-defined
cohorts with their own shifted ERC windows. Think of 4w/8w/12w as three read-outs of
the *same* ended-rental cohort at increasingly long follow-up horizons (a
survival-curve view), not three different populations:

```
denominator(M)      — identical for 4w, 8w, and 12w
numerator_4w(M)      = signed by day 28
numerator_8w(M)      = signed by day 56  (⊇ numerator_4w)
numerator_12w(M)     = signed by day 84  (⊇ numerator_8w)
```

The metric is read by **maturation cohort**, not by calendar occurrence: a listing is
assigned to cohort month **M** when its 28-day maturation window (`erc_dt` + 28 days)
falls inside calendar month **M** — not when `erc_dt` itself falls in month M. This
means the ERC date range used for a given cohort month starts and ends inside the
*previous* calendar month (see Calculation below). Naively grouping by
`date_trunc('month', erc_dt)` produces a different (wrong) number because it mixes
listings whose 28-day window hasn't fully matured yet.

**Important — 8w/12w maturity lags behind the cohort month label.** Because the
cohort/denominator is anchored to the 4w (28-day) maturation window, a cohort month
M's *label* only guarantees the 4w number is fully matured by the end of month M. The
8w number for that same cohort doesn't finish maturing until ~4 weeks later, and the
12w number until ~8 weeks later. **A live query against a recent cohort month will
show 8w/12w values that are still climbing** — this is not a bug, it's the same
"MTD" phenomenon that applies to the current month's 4w number, just extended
further out on the calendar for the higher horizons.

## Related Business Entities

- Termination

## MBR

- Post Contract

## Glossary and Synonyms

- **ER2RR**, **ER2RR 4W / 8W / 12W**, **Ended Rental to Re-Rental**, **landlord
  retention rate**, **re-rental rate** → this metric family

## Scope

**Included**: house listings (`sk_house_listing`) with a non-canceled termination
(`dim_termination.status != 'CANCELED'`) whose contract is not `MX` and not
administered by `OWNER` or `THIRD_PARTY`, and that have a valid `erc_dt`
(`sk_ended_rental_confirmed_date`).

**Excluded**: canceled terminations, `MX` contracts, listings administered by
`OWNER`/`THIRD_PARTY`, and rows without `sk_house_listing`.

## Calculation

Naive approach: group by the calendar month of `erc_dt` and check whether `cs_dt`
falls within N days. This is wrong because it includes listings whose window extends
into the *next* calendar month and excludes ERCs from the tail of the *prior* month
whose window matures inside the current one — the cohort would mix
partially-matured and fully-matured populations and month-over-month comparisons
would not be apples-to-apples.

The correct calculation groups listings by **the calendar month in which their
28-day (4w) maturation window lands** — this grouping is shared by all three
horizons — then computes, for a given horizon `N` ∈ {28, 56, 84} days:

```
ER2RR_Nw(M) = numerator_Nw(M) / denominator(M)
```

- **denominator(M)**: distinct `sk_house_listing` with `erc_dt` inside the **4w**
  maturation window of month M (see Cohort window definition below). **Same for
  4w, 8w, and 12w** — do not recompute a separate window per horizon.
- **numerator_Nw(M)**: the subset of denominator(M) whose `cs_dt` is not null and
  falls **on or before** `erc_dt + N days` (N = 28 / 56 / 84 for 4w / 8w / 12w).
  **There is no lower bound on `cs_dt` relative to `erc_dt`** — a next contract
  signed *before* the ERC date (e.g. the tenant lined up the next renter before the
  exit inspection was formally confirmed) still counts, as long as the signature
  happened by `erc_dt + N days`. This absence of a lower bound was validated on the
  4w number first (see Dos and Don'ts below for the concrete before/after numbers),
  then confirmed to hold identically for 8w/12w.

### Cohort window definition

For cohort month **M** (first calendar day = `month_start`), using the **4w (28-day)**
formula — this is the one and only cohort window, reused for 8w and 12w:

```
window_start(M) = month_start - 28 days
window_end(M)   = (month_start + 1 month) - 29 days   -- i.e. last day of M, minus 28 days
```

| Cohort month | window_start | window_end |
| :--- | :--- | :--- |
| Janeiro/26 | 2025-12-04 | 2026-01-03 |
| Fevereiro/26 | 2026-01-04 | 2026-01-31 |
| Março/26 | 2026-02-01 | 2026-03-03 |
| Abril/26 | 2026-03-04 | 2026-04-02 |
| Maio/26 | 2026-04-03 | 2026-05-03 |
| Junho/26 | 2026-05-04 | 2026-06-02 |

A listing belongs to cohort month M if and only if `erc_dt BETWEEN window_start(M) AND window_end(M)`.

**MTD (partial current month) variant:** for a cohort month that hasn't closed yet,
cap `window_end(M)` at the last date whose 28-day window has actually had time to
mature given the data as-of date, instead of using the full-month `window_end(M)`
formula above. Precedent (2026-07-23, data as-of that date, MTD cutoff requested for
21/07): July/26 MTD used `window_start = 2026-06-03`, `window_end = 2026-06-21`
(rather than the full-month `2026-07-03`). Confirm the exact MTD window with the
Data Steward per request — it is not a fixed offset, it depends on the requested
as-of date.

### Weekly cohort window definition

Same metric, **weekly cadence** instead of monthly — same denominator/cohort logic
(anchored to the 4w/28-day window; 8w/12w reuse it, only the numerator threshold
changes). QuintoAndar's week convention is **Monday–Sunday** (`day_of_week(...) = 1`
on Monday; Trino's `date_trunc('week', date)` returns that Monday).

Because weeks are a fixed 7 days (unlike months), the formula is symmetric — no
`+1 month / -29 days` asymmetry:

```
window_start(W) = mature_week_monday - 28 days
window_end(W)   = mature_week_monday - 22 days   -- i.e. window_start + 6 days
```

where `mature_week_monday` is the Monday of the week being reported (the week in
which the 28-day maturation window lands — same "maturation cohort, not calendar
occurrence" principle as the monthly view).

**Validated 2026-07-24** against a value the Data Steward tested independently in
another session: week of **13/07/26** (Monday) matures the ERC week **15/06–21/06**
(`2026-07-13 - 28 = 2026-06-15`; `2026-07-13 - 22 = 2026-06-21`) → denominator
**2.680**, numerator (4w) **1.125** — exact match.

| Semana de maturação (2ª-feira) | ERC de | ERC até |
| :--- | :--- | :--- |
| 04/05/26 | 06/04/26 | 12/04/26 |
| 11/05/26 | 13/04/26 | 19/04/26 |
| 18/05/26 | 20/04/26 | 26/04/26 |
| 13/07/26 | 15/06/26 | 21/06/26 |

**MTD (partial current week):** same principle as the monthly MTD — cap
`window_end(W)` at the ERC date whose N-day window has actually had time to mature
given the as-of date, rather than the full 7-day window.

### Canonical Filter

Apply on `dw_offboarding.fact_house_listing_terminations` (`f`) joined to
`dw_offboarding.dim_termination` (`d`) and `dw_rent.dim_contract` (`dc`):

```sql
d.status != 'CANCELED'
AND dc.country_code != 'MX'
AND dc.rental_administrator NOT IN ('OWNER', 'THIRD_PARTY')
AND f.sk_house_listing IS NOT NULL
```

**Warning**: skipping the `dc.rental_administrator` or `dc.country_code` filters
inflates both numerator and denominator with owner-administered / third-party /
Mexico listings that are out of scope for this metric.

### Nuances

- `erc_dt` = `TRY(DATE(DATE_PARSE(CAST(NULLIF(f.sk_ended_rental_confirmed_date, -1) AS VARCHAR), '%Y%m%d')))`
- `cs_dt` = `TRY(DATE(DATE_PARSE(CAST(NULLIF(f.sk_next_contract_signature_date, -1) AS VARCHAR), '%Y%m%d')))`
- Both are date-keys (`sk_*`) stored as `YYYYMMDD` integers with `-1` meaning "no
  date"; always run them through `NULLIF(..., -1)` before parsing.
- `cs_dt` sourced from `sk_next_contract_signature_date` matches `dw_rent.dim_contract.ts_signature`
  (joined via `sk_next_contract = dim_contract.sk_contract`) for every populated row —
  confirmed by direct comparison 2026-07-23. Either source is equally valid; the
  date-key stays the primary source since it avoids an extra join.
- Dedup at the `sk_house_listing` grain with `COUNT(DISTINCT ...)` — a listing can
  technically appear more than once in the base termination fact.
- **Join key**: cohort assignment is purely a function of `erc_dt` vs. the
  `window_start`/`window_end` pair for each candidate month — no join to an external
  weight/parameter table is required.
- **Fallback**: none needed; a listing with a null `erc_dt` simply cannot belong to
  any cohort and is excluded from both numerator and denominator.
- `fact_house_listing_terminations` is loaded as a **single full daily snapshot**
  (one uniform `ts_load` value across the whole table on any given day, confirmed
  2026-07-23) — there is no per-row insert/update history preserved. This means a
  manual pull from an earlier day **cannot** be reproduced later by filtering on
  `ts_load`; if you need a reproducible "as of `<date>`" number, the pull has to
  happen on that date (or from a table that keeps history).

## Dos and Don'ts

**Do:**
- Assign cohort month by where the **28-day-matured (4w)** window lands, never by
  the calendar month of `erc_dt` directly — and reuse that **same** window/denominator
  for 8w and 12w. Do not shift the ERC window by 56 or 84 days for those horizons.
- Count numerator/denominator as **distinct `sk_house_listing`**, not row counts.
- Require `cs_dt <= erc_dt + N days` for the numerator (N=28/56/84) — **no lower
  bound** on `cs_dt` relative to `erc_dt`.
- For recent/current cohort months, expect 8w and 12w to read **lower than their
  eventual matured value** (they need more elapsed time than 4w to fully mature) —
  state the data as-of date whenever quoting them.

**Don't:**
- Don't group by `date_trunc('month', erc_dt)` — that is the naive/wrong path
  described above.
- Don't add `cs_dt >= erc_dt` to the numerator filter — this was a real bug found
  and fixed on 2026-07-23 (`FILTER` previously required
  `e.cs_dt BETWEEN e.erc_dt AND date_add('day', 28, e.erc_dt)`, i.e. a silent lower
  bound not part of the metric's true definition). It silently excluded listings
  whose next contract was signed before the ERC date, undercounting the numerator by
  ~35–40% (e.g. Jan/26 read numerator 2.883 / 26.2% instead of the correct 4.887 /
  44.4%) while leaving the denominator untouched. Root cause found by comparing
  Trino output against the Data Steward's manual reference values for Jan–Abr/26
  (all four matched exactly once the lower bound was removed).
- Don't redefine the ERC cohort window per horizon (e.g. `month_start - 56` for 8w).
  The denominator is identical across 4w/8w/12w — only the numerator's day-threshold
  changes.
- Don't forget the `country_code != 'MX'` / `rental_administrator NOT IN ('OWNER',
  'THIRD_PARTY')` / `status != 'CANCELED'` filters — under-filtering inflates both
  numerator and denominator.
- Don't compare a live-recomputed 8w/12w number for a recent cohort against an older
  manual snapshot and assume something's wrong — re-check the as-of date first (see
  the Reference values note under Golden Queries for a concrete example of this).
- Don't hardcode the reference cohorts below as validation without re-deriving them —
  recompute from the golden query; they should match exactly (not just "small
  rounding differences") for any cohort month whose relevant horizon has already
  fully matured as of the data as-of date.

## Golden Queries

Computes ER2RR 4w/8w/12w per maturation cohort month in one pass. The
`termination_base` CTE reproduces the ERC/CS extraction pattern from the upstream
terminations query (only the two columns needed for this metric — `erc_dt` and
`cs_dt` — are kept); the `cohort_window` CTE and final aggregation are exclusive to
this metric. **The same `cohort_window` (28-day/4w formula) drives all three
horizons** — only the `FILTER` day-threshold changes per column.

```sql
WITH termination_base AS (
    -- Component: minimal ERC/next-contract-signature extraction for terminated listings.
    SELECT DISTINCT
        f.sk_house_listing,
        TRY(DATE(DATE_PARSE(CAST(NULLIF(f.sk_ended_rental_confirmed_date, -1) AS VARCHAR), '%Y%m%d'))) AS erc_dt,
        TRY(DATE(DATE_PARSE(CAST(NULLIF(f.sk_next_contract_signature_date, -1) AS VARCHAR), '%Y%m%d'))) AS cs_dt
    FROM dw_offboarding.fact_house_listing_terminations AS f
    INNER JOIN dw_offboarding.dim_termination AS d ON f.sk_termination = d.sk_termination
    LEFT JOIN dw_rent.dim_contract AS dc ON f.sk_contract = dc.sk_contract
    WHERE
        d.status != 'CANCELED'
        AND dc.country_code != 'MX'
        AND dc.rental_administrator NOT IN ('OWNER', 'THIRD_PARTY')
        AND f.sk_house_listing IS NOT NULL
),

erc_events AS (
    SELECT sk_house_listing, erc_dt, cs_dt
    FROM termination_base
    WHERE erc_dt IS NOT NULL
),

cohort_window AS (
    -- One row per candidate cohort month, with its 4w maturation window
    -- (this window is shared by 4w/8w/12w — do not recompute per horizon).
    SELECT
        month_start,
        date_add('day', -28, month_start) AS window_start,
        date_add('day', -29, date_add('month', 1, month_start)) AS window_end
    FROM (
        SELECT dt AS month_start
        FROM UNNEST(SEQUENCE(DATE '2025-01-01', DATE '2027-01-01', INTERVAL '1' MONTH)) AS t(dt)
    )
)

SELECT
    date_format(cw.month_start, '%Y-%m') AS cohort_month,
    COUNT(DISTINCT e.sk_house_listing) AS denominator_erc,

    COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 28, e.erc_dt)
    ) AS numerator_4w,
    ROUND(100.0 * COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 28, e.erc_dt)
    ) / NULLIF(COUNT(DISTINCT e.sk_house_listing), 0), 1) AS er2rr_4w_pct,

    COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 56, e.erc_dt)
    ) AS numerator_8w,
    ROUND(100.0 * COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 56, e.erc_dt)
    ) / NULLIF(COUNT(DISTINCT e.sk_house_listing), 0), 1) AS er2rr_8w_pct,

    COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 84, e.erc_dt)
    ) AS numerator_12w,
    ROUND(100.0 * COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 84, e.erc_dt)
    ) / NULLIF(COUNT(DISTINCT e.sk_house_listing), 0), 1) AS er2rr_12w_pct

FROM cohort_window AS cw
JOIN erc_events AS e ON e.erc_dt BETWEEN cw.window_start AND cw.window_end
GROUP BY 1, cw.month_start
ORDER BY cw.month_start
```

**Reference values** (Trino, `delta` catalog, data as-of 2026-07-23). Jan–Mai/26
confirmed exact by the Data Steward for all three horizons (fully matured already),
including the 8w extension (Jan/26 56.2%, Fev/26 58.3% matched exactly). Junho/26 12w
(55.8% live vs. 55.1% in the Steward's reference) and Julho/26 8w/12w (48.4% live vs.
47.2% in the Steward's reference) **are not yet fully matured** as of this data as-of
date and will read higher than an earlier manual pull: the Steward's own base only had
ERCs through 19/07, while the live Trino table (as-of 2026-07-23) had ~4 more days of
trailing signatures land for these still-immature cohorts. Since
`fact_house_listing_terminations` is a single uniform daily snapshot with no per-row
history (see Nuances above), the Steward's earlier state cannot be reconstructed
retroactively from this table — re-pull on the date you need a pinned number:

| Cohort month | Denominador | Num. 4w | ER2RR 4w | Num. 8w | ER2RR 8w | Num. 12w | ER2RR 12w |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Janeiro/26 | 11.010 | 4.887 | 44.4% | 6.190 | 56.2% | 6.722 | 61.1% |
| Fevereiro/26 | 9.896 | 4.833 | 48.8% | 5.771 | 58.3% | 6.142 | 62.1% |
| Março/26 | 13.247 | 6.510 | 49.1% | 7.653 | 57.8% | 8.117 | 61.3% |
| Abril/26 | 13.589 | 6.348 | 46.7% | 7.519 | 55.3% | 8.067 | 59.4% |
| Maio/26 | 12.190 | 5.513 | 45.2% | 6.592 | 54.1% | 7.110 | 58.3% |
| Junho/26 | 13.000 | 5.874 | 45.2% | 6.998 | 53.8%¹ | 7.254 | 55.8%¹ |
| Julho/26 (MTD 21/07, janela ERC 03/06–21/06) | 7.539 | 3.262 | 43.3% | 3.650 | 48.4%¹ | 3.650 | 48.4%¹ |

¹ Not fully matured as of 2026-07-23 — will continue climbing (never falls) as more
signatures land. Junho/26's 12w window doesn't close until ~25/08/26; Julho/26 MTD's
8w/12w windows barely started. Re-pull on the day you need a stable number and record
the as-of date alongside it.

### Golden Query — weekly cadence

Same structure as the monthly query — only `cohort_window` changes to a fixed
7-day `cohort_week` (Monday-anchored), reusing the same `termination_base` /
`erc_events` CTEs above:

```sql
cohort_week AS (
    -- One row per candidate mature week (Monday), with its 4w maturation window.
    SELECT
        wk AS mature_week_start,
        date_add('day', -28, wk) AS window_start,
        date_add('day', -22, wk) AS window_end
    FROM (
        SELECT dt AS wk
        FROM UNNEST(SEQUENCE(DATE '2025-01-06', DATE '2027-01-04', INTERVAL '7' DAY)) AS t(dt)
        -- start date must be a Monday; adjust the range as needed
    )
)

SELECT
    CAST(cw.mature_week_start AS VARCHAR) AS semana_maturacao,
    COUNT(DISTINCT e.sk_house_listing) AS denominador,
    COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 28, e.erc_dt)
    ) AS numerator_4w,
    COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 56, e.erc_dt)
    ) AS numerator_8w,
    COUNT(DISTINCT e.sk_house_listing) FILTER (
        WHERE e.cs_dt IS NOT NULL AND e.cs_dt <= date_add('day', 84, e.erc_dt)
    ) AS numerator_12w
FROM cohort_week AS cw
JOIN erc_events AS e ON e.erc_dt BETWEEN cw.window_start AND cw.window_end
GROUP BY 1, cw.mature_week_start
ORDER BY cw.mature_week_start
```

**Reference values, weekly cadence** (Trino, data as-of 2026-07-24). 4w confirmed
exact for the 13/07/26 week; 8w/12w for recent weeks are shown for completeness but
are **far from matured** (a week's 8w/12w number needs 8–12 weeks of real elapsed
time, not just a Monday label, to stop climbing):

| Semana maturação | ERC de–até | Denominador | Num. 4w | ER2RR 4w | Num. 8w | ER2RR 8w¹ | Num. 12w | ER2RR 12w¹ |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 22/06/26 | 25/05–31/05 | 2.644 | 1.165 | 44.1% | 1.396 | 52.8% | 1.404 | 53.1% |
| 29/06/26 | 01/06–07/06 | 3.038 | 1.424 | 46.9% | 1.665 | 54.8% | 1.665 | 54.8% |
| 06/07/26 | 08/06–14/06 | 3.299 | 1.396 | 42.3% | 1.586 | 48.1% | 1.586 | 48.1% |
| **13/07/26** | **15/06–21/06** | **2.680** | **1.125** | **42.0%** | 1.230 | 45.9%¹ | 1.230 | 45.9%¹ |

¹ Not remotely matured as of 2026-07-24 — the 13/07/26 week's 8w window doesn't close
until ~16/08/26 and its 12w window until ~13/09/26. Treat weekly 8w/12w numbers for
any week matured in the last ~2 months as provisional; only 4w is reliably matured
week-to-week at this granularity.
