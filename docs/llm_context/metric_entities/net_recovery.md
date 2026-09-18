# Net Recovery

## Ownership

**Data Owner:**
- maxsuel.alves@quintoandar.com.br

**Data Steward:**
- maxsuel.alves@quintoandar.com.br

## Overview

**Net Recovery** measures collections performance on QuintoAndar's tenant overdue invoice portfolio (T2 methodology) — how much of the amount owed by delinquent tenants has actually been recovered. This entity covers two closely related official metrics: **Net Recovery** (the absolute monetary amount recovered) and **% Net Recovery** (that amount expressed as a percentage of the total amount due in the same population). Which one applies depends on the question shape: a value question ("how much was recovered this week") resolves to **Net Recovery**; a rate question ("what percentage of the portfolio was recovered") resolves to **% Net Recovery**, which requires comparing recovered amount against the due-amount base.

**This entity exists exclusively for tenant (inquilino) collections.** Landlord (Proprietário) Net Recovery is a separate, differently-scoped metric computed from a different source table/domain and is out of scope for this document.

## Related Domain Entities

- **T2 Overdue Portfolio** (`t2_overdue_portfolio_context.md`) — full field glossary (`advisory`, `segmentation`, `portfolio` value dictionaries, external/internal advisory split), table routing, and exploratory/component metrics for `sandbox.t2_fact_overdue_portfolio_timeline`. URN: `urn:li:dataset:(urn:li:dataPlatform:trino,hive.sandbox.t2_fact_overdue_portfolio_timeline,PROD)`

## Catalog

| Metric | Type |
| :---- | :---- |
| Net Recovery | OKR |
| % Net Recovery | OKR |

## Glossary and Synonyms

- **Net Recovery**, **recuperação** → this entity — typically the absolute recovered-amount member metric
- **% Net Recovery**, **%Net Recovery**, **Taxa de Recuperação**, **% recuperação** → this entity — the percentage member metric
- **Net Recovery (Proprietários)** / landlord recovery / recuperação de proprietários → near-miss — a distinct metric for the Landlord (Proprietário) domain, computed from a different source table; do not resolve against this entity

## Scope

**Included**: tenant (inquilino) overdue invoices in the T2 collections portfolio classified as directly collectable (`collectable_delinquent_portfolio = TRUE`) — i.e., invoices with no active parent negotiation, or whose negotiation was cancelled.

**Excluded**: invoices currently under an active (non-cancelled) negotiation agreement (the "regularized" portfolio, tracked separately); Landlord (Proprietário) Net Recovery, sourced from a different table/domain and not covered by this entity.

## Calculation

The correct calculation is:

```
Net Recovery = SUM(net_recovered_amount)
% Net Recovery = SUM(net_recovered_amount) / SUM(due_amount)
```

where `due_amount` and `net_recovered_amount` are read per invoice, per reference date, from the T2 overdue portfolio timeline, restricted to the Canonical Filter below.

The source table carries one row per invoice per calendar day for as long as the invoice appears in the timeline (from becoming overdue until the end of its payment month). Summing `due_amount` / `net_recovered_amount` across a date range, or grouping by `business_day` without first collapsing the daily fan-out, multiplies the same invoice's balance across every day it appears in the timeline — inflating both the numerator and the denominator.

### Canonical Filter

Apply on `sandbox.t2_fact_overdue_portfolio_timeline`:

```sql
collectable_delinquent_portfolio = TRUE
AND portfolio NOT LIKE '%eviction%'
```

**Warning**: Omitting `collectable_delinquent_portfolio = TRUE` includes invoices under an active negotiation (the regularized portfolio), which are not part of the official Net Recovery universe and distort the rate.

**The `portfolio NOT LIKE '%eviction%'` exclusion is mandatory, confirmed live in Trino on 2026-09-18** — `collectable_delinquent_portfolio = TRUE` does *not*, by itself, exclude invoices in `portfolio = 'm) evictions'` (20,593 rows / R$63.3M due / R$5.0M recovered on the 2026-08-31 snapshot). The official production report `sandbox.rpt_collections_tenants_portfolio_timeline` excludes this population before aggregating. Omitting it when computing an **overall** % Net Recovery (not broken out by `portfolio`) blends in the eviction-stage rate and understates the result — confirmed impact on 2026-08-31: 13.14% (wrong, eviction included) vs. 13.58% (correct). When already grouping by `portfolio` bucket, this is naturally handled by filtering out the `m) evictions` row from the output, but a query that computes the metric without that grouping needs the explicit filter.

### Nuances

No external weight or parameter table — both metrics are direct `SUM` aggregations.

- **Business-day alignment**: to compare the same day-of-month position across different months, group by `business_day` and additionally filter `is_last_business_days = TRUE` — calendar dates that share a business-day ordinal (e.g., a weekend or holiday carrying the prior business day's count) would otherwise duplicate the balance into that ordinal.
- **Date-based views**: when slicing directly by `dt_reference` (a single calendar date), `is_last_business_days` is not needed — the date is already a grain key, so each invoice contributes exactly one row.
- **Month-end snapshot**: add `dt_reference = dt_month_end` to get the true closing position for a month, rather than just the last business day.
- **Recovery-method decomposition**: breaking `% Net Recovery` down by `recovery_method` (categories `b) Original Payment` through `f) Written-down w/o Negotiation`) sums back to the total; `a) Open` never contributes, since its `net_recovered_amount` is always zero.
- **Decimal division**: force decimal division in the numerator (e.g., `* 1.0000`) to avoid integer-division truncation in Trino.
- **Rolling window convention**: production views commonly scope to a ~12–13 month rolling window because the source table is large/costly to scan fully — this is a performance convention, not a fixed business rule, and the window can be adjusted per analysis need.
- **Cutting by `advisory` or `segmentation`**: both are native fields on this table (not a join to another domain) — full value dictionaries, the external/internal advisory split, and a Simpson's-paradox warning about comparing recovery rate across `advisory` without controlling for `segmentation`/aging are documented in `t2_overdue_portfolio_context.md` (Glossary and Synonyms / Dos and Don'ts), along with two ready-to-use monthly trend Golden Queries for each cut.
- **Performance vs. Target / OKR — do not ask the requester for the target value, it is derivable from data.** Net Recovery has an official target comparison: join `sandbox.t2_fact_overdue_portfolio_timeline` to `sandbox.planning_performance_fact_daily_targets` on `dt_reference` (add `business_day` for MTD-locked comparisons across months, same convention as the rest of this metric). The full `portfolio` bucket → target column mapping — confirmed both by the requester and by the actual production report query (`rpt_collections_tenants_portfolio_timeline`) — lives in `t2_overdue_portfolio_context.md` (Glossary and Synonyms → "Target mapping"). Default to the **new-segmentation** target columns documented there (`active_new_defaulter_first_payment_default_recovery`, `active_new_defaulter_under_mob3_recovery`, `total_active_new_defaulter_recovery`, `active_stock_recovery`, `ended_new_defaulter_recovery`, `ended_stock_31_90/91_180/181_360/361_1440/over1440_recovery`, `active_effectiveness`, `ended_effectiveness`); only use the retired "old segmentation" columns when a comparison against them is explicitly requested. See the ready-to-use Golden Query below.
- **New-segmentation targets only exist from August 2026 onward — confirmed live in Trino (2026-09-18).** Requesting "Net Recovery vs. Target" for June or July 2026 (portfolio-bucket columns, not `active_effectiveness`/`ended_effectiveness`) returns a **null target** under the default mapping — those columns simply weren't populated yet for those months, this is not a data gap. The retired "old segmentation" equivalents (e.g. `net_recovery_fpd`, `net_recovery_active_stock`) do carry values for June/July, but only cover buckets `a` and `d` — there is no old-segmentation equivalent readily available for buckets `b`, `c`, `f`–`k` in that window. See `t2_overdue_portfolio_context.md` (Glossary → "Target mapping") for the exact per-column retirement dates found.

**Fallback**: not applicable — no parameter table is involved.

## Dos and Don'ts

**Do:**

- Always apply `collectable_delinquent_portfolio = TRUE` **and** `portfolio NOT LIKE '%eviction%'`.
- Apply `is_last_business_days = TRUE` whenever grouping or comparing by `business_day`.
- Add `dt_reference = dt_month_end` for month-end closing views.
- Force decimal division to avoid truncation.
- When asked for performance **vs. Target / OKR**, derive the target automatically by joining `sandbox.planning_performance_fact_daily_targets` using the mapping in `t2_overdue_portfolio_context.md` — don't ask the requester to supply the target value.

**Don't:**

- Don't sum `due_amount` / `net_recovered_amount` across multiple `dt_reference` values, or group by `business_day`, without first collapsing the daily fan-out — it double- or triple-counts the same invoice.
- Don't include invoices under an active negotiation — they are out of scope for this metric.
- Don't compute an **overall** % Net Recovery (not broken out by `portfolio`) with only `collectable_delinquent_portfolio = TRUE` and no `portfolio` exclusion — it silently blends in eviction-stage invoices and understates the result (confirmed impact above).
- Don't confuse this entity with landlord (Proprietário) Net Recovery — different source table and domain.
- Don't ask the requester for the target value when a target/OKR comparison is requested — it is always derivable from `sandbox.planning_performance_fact_daily_targets` via the confirmed mapping (see Nuances above and the Golden Query below).

## Golden Queries

Overall **Net Recovery** and **% Net Recovery** as of a single point-in-time reference date. No business-day dedup is needed here since `dt_reference` is already a grain key.

```sql
SELECT
    SUM(net_recovered_amount) AS net_recovery,
    SUM(net_recovered_amount) * 1.0000 / SUM(due_amount) AS pct_net_recovery
FROM sandbox.t2_fact_overdue_portfolio_timeline
WHERE collectable_delinquent_portfolio = TRUE
  AND portfolio NOT LIKE '%eviction%' -- mandatory, see Canonical Filter note
  AND dt_reference = DATE '2026-09-07' -- replace with the desired reference date
```

**% Net Recovery** broken down by aging bucket, at month-end closing position, over a trailing 13-month window.

```sql
SELECT
    delay_contamined_range AS delay_contamined_range,
    date_trunc('day', CAST(dt_month_end AS TIMESTAMP)) AS dt_month_end,
    SUM(due_amount) AS "Due Amount",
    SUM(net_recovered_amount) AS "Net Recovery"
FROM (
    SELECT *
    FROM sandbox.t2_fact_overdue_portfolio_timeline
    WHERE is_last_business_days = TRUE
) AS virtual_table
WHERE (
    date_trunc('month', dt_reference) BETWEEN date_add('month', -13, date_trunc('month', current_date)) AND date_add('day', -1, current_date)
  )
  AND (dt_reference = dt_month_end)
  AND (collectable_delinquent_portfolio = TRUE)
  AND (portfolio NOT LIKE '%eviction%') -- mandatory, see Canonical Filter note
GROUP BY delay_contamined_range, date_trunc('day', CAST(dt_month_end AS TIMESTAMP))
ORDER BY "Due Amount" DESC
LIMIT 10000
```

Cumulative daily evolution of **% Net Recovery** by business-day position within the month, over a trailing 12-month window — enables comparing the same day-of-month point across different months.

```sql
SELECT
    business_day AS business_day,
    DATE_FORMAT(dt_month_end, '%y-%m') AS "Month",
    SUM(net_recovered_amount) * 1.0000 / SUM(due_amount) AS "% Net Recovery"
FROM (
    SELECT *
    FROM sandbox.t2_fact_overdue_portfolio_timeline
    WHERE is_last_business_days = TRUE
) AS virtual_table
WHERE (
    date_trunc('month', dt_reference) BETWEEN date_add('month', -12, date_trunc('month', current_date)) AND date_add('day', -1, current_date)
  )
  AND (collectable_delinquent_portfolio = TRUE)
  AND (portfolio NOT LIKE '%eviction%') -- mandatory, see Canonical Filter note
GROUP BY business_day, DATE_FORMAT(dt_month_end, '%y-%m')
ORDER BY "% Net Recovery" DESC
LIMIT 10000
```

Decomposition of **% Net Recovery** by `recovery_method`, by business-day position within the month, over a trailing 13-month window — shows each recovery channel's contribution to the total.

```sql
SELECT
    business_day AS business_day,
    date_trunc('day', CAST(dt_month_end AS TIMESTAMP)) AS dt_month_end,
    SUM(CASE WHEN recovery_method = 'b) Original Payment' THEN net_recovered_amount END) * 1.000 / SUM(due_amount) AS "b) Original Payment",
    SUM(CASE WHEN recovery_method = 'c) Negotiation Oneshot Payment' THEN net_recovered_amount END) * 1.000 / SUM(due_amount) AS "c) Negotiation Oneshot Payment",
    SUM(CASE WHEN recovery_method = 'd) Negotiation Card Payment' THEN net_recovered_amount END) * 1.000 / SUM(due_amount) AS "d) Negotiation Card Payment",
    SUM(CASE WHEN recovery_method = 'e) Negotiation Downpayment' THEN net_recovered_amount END) * 1.000 / SUM(due_amount) AS "e) Negotiation Downpayment",
    SUM(CASE WHEN recovery_method = 'f) Written-down w/o Negotiation' THEN net_recovered_amount END) * 1.000 / SUM(due_amount) AS "f) Written-down w/o Negotiation"
FROM (
    SELECT *
    FROM sandbox.t2_fact_overdue_portfolio_timeline
    WHERE is_last_business_days = TRUE
) AS virtual_table
WHERE (
    date_trunc('month', dt_reference) BETWEEN date_add('month', -13, date_trunc('month', current_date)) AND date_add('day', -1, current_date)
  )
  AND (collectable_delinquent_portfolio = TRUE)
  AND (portfolio NOT LIKE '%eviction%') -- mandatory, see Canonical Filter note
GROUP BY business_day, date_trunc('day', CAST(dt_month_end AS TIMESTAMP))
ORDER BY SUM(CASE WHEN recovery_method = 'b) Original Payment' THEN net_recovered_amount END) * 1.000 / SUM(due_amount) ASC
LIMIT 10000
```

**% Net Recovery vs. Target, by `portfolio` bucket, MTD-locked, trailing 13 months** — the query to run whenever a target/OKR comparison is requested; do not ask the requester for the target number. Mirrors the confirmed production mapping in `t2_overdue_portfolio_context.md`. **Validation note:** structure mirrors the already-validated pattern used for this same comparison earlier in this project and the confirmed production `CASE` logic — re-run with `--preview-only` before citing a number if the Trino session was re-authenticated since this was written.

```sql
WITH t2_data AS (
    SELECT
        dt_reference, dt_month_start, dt_month_end, business_day, mtd,
        portfolio,
        SUM(net_recovered_amount) AS net_recovered_amount,
        SUM(due_amount) AS due_amount
    FROM sandbox.t2_fact_overdue_portfolio_timeline
    WHERE collectable_delinquent_portfolio = TRUE
      AND portfolio NOT LIKE '%eviction%' -- mandatory, see Canonical Filter note (already implied here since portfolio is grouped, kept explicit for consistency)
      AND is_last_business_days = TRUE
    GROUP BY 1, 2, 3, 4, 5, 6
),
targets_data AS (
    SELECT
        dt_reference,
        active_new_defaulter_first_payment_default_recovery,
        active_new_defaulter_under_mob3_recovery,
        total_active_new_defaulter_recovery,
        active_stock_recovery,
        ended_new_defaulter_recovery,
        ended_stock_31_90_recovery,
        ended_stock_91_180_recovery,
        ended_stock_181_360_recovery,
        ended_stock_361_1440_recovery,
        ended_stock_over1440_recovery
    FROM sandbox.planning_performance_fact_daily_targets
)
SELECT
    t2.portfolio,
    date_trunc('month', t2.dt_month_end) AS mes,
    t2.net_recovered_amount * 1.0000 / t2.due_amount AS pct_net_recovery,
    CASE t2.portfolio
        WHEN 'a) active-new-defaulter-first-payment-default' THEN tgt.active_new_defaulter_first_payment_default_recovery
        WHEN 'b) active-new-defaulter-under-mob3' THEN tgt.active_new_defaulter_under_mob3_recovery
        WHEN 'c) active-new-defaulter' THEN tgt.total_active_new_defaulter_recovery
        WHEN 'd) active-stock' THEN tgt.active_stock_recovery
        WHEN 'f) ended-new-defaulter' THEN tgt.ended_new_defaulter_recovery
        WHEN 'g) ended-stock-31-90' THEN tgt.ended_stock_31_90_recovery
        WHEN 'h) ended-stock-91-180' THEN tgt.ended_stock_91_180_recovery
        WHEN 'i) ended-stock-181-360' THEN tgt.ended_stock_181_360_recovery
        WHEN 'j) ended-stock-361-1440' THEN tgt.ended_stock_361_1440_recovery
        WHEN 'k) ended-stock-over1440' THEN tgt.ended_stock_over1440_recovery
    END AS target
FROM t2_data AS t2
LEFT JOIN targets_data AS tgt ON t2.dt_reference = tgt.dt_reference
WHERE t2.business_day = t2.mtd
  AND t2.dt_reference >= date_add('month', -13, date_trunc('month', current_date))
ORDER BY t2.portfolio, mes DESC
```

**Δ% vs. Target — confirmed formula (from the live production Superset query, "Δ% Target" column):**

```
Δ% Target = (result / target) - 1
```

This is a **relative** difference (e.g., result 20% above target renders as `+20%`, not `+20 p.p.`) — do not confuse it with the absolute percentage-point gap (`result - target`). Same formula applies to the other Δ columns in the reference charts (`Δ% M-1`, `Δ% YoY`, `Δ% BM 12M`, `Δ% Méd. 3M/6M/12M`), each dividing the current-month rate by the comparison rate (or, for the rolling-average variants, by the average of the corresponding trailing months) and subtracting 1.

Note: `portfolio` bucket `e) active-ongoing-deal` has no target column — the `CASE` above correctly returns `NULL` for it, matching the target-setting process's own scope (see `t2_overdue_portfolio_context.md`). `active_effectiveness` / `ended_effectiveness` (cut by `contract_status` instead of `portfolio`) are a separate comparison, not by bucket — see the domain doc for that mapping.

**"Carteira Ativa" (active book) and "Carteira Finalizada" (ended book) — confirmed official bucket + target groupings, from two live Superset golden queries shared directly by the requester on 2026-09-18:**

| Grouping | `portfolio` buckets | Target columns (in `sandbox.planning_performance_fact_daily_targets`) |
|---|---|---|
| **Carteira Ativa** | `a) active-new-defaulter-first-payment-default`, `b) active-new-defaulter-under-mob3`, `c) active-new-defaulter`, `d) active-stock` | `active_new_defaulter_first_payment_default_recovery`, `active_new_defaulter_under_mob3_recovery`, `total_active_new_defaulter_recovery`, `active_stock_recovery` |
| **Carteira Finalizada** | `f) ended-new-defaulter`, `g) ended-stock-31-90`, `h) ended-stock-91-180`, `i) ended-stock-181-360`, `j) ended-stock-361-1440`, `k) ended-stock-over1440` | `ended_new_defaulter_recovery`, `ended_stock_31_90_recovery`, `ended_stock_91_180_recovery`, `ended_stock_181_360_recovery`, `ended_stock_361_1440_recovery`, `ended_stock_over1440_recovery` |

`e) active-ongoing-deal` and `l) ended-ongoing-deal` are excluded from **both** named groupings — confirmed by the official charts, not just by the target mapping having no column for them.

Both official queries filter `collectable_delinquent_portfolio = TRUE AND is_last_business_days = TRUE`, group by `portfolio`, and compare `SUM(net_recovered_amount)/SUM(due_amount)` against `MAX(portfolio_target)` for the current month (plus M-1 through M-4, YoY, and rolling-average deltas — Superset-side presentation logic, not part of this entity's core calculation). This matches — and confirms correct — the bucket-level target mapping and the trend Golden Query above. See Superset Golden Assets below for the chart references.

**Worked example (2026-08-31 month-end close, `reference_view = 'b) Fechamento'`) — confirmed live in Trino on 2026-09-18:**

| `portfolio` bucket | Grouping | % Net Recovery | Target |
|---|---|---|---|
| `a) active-new-defaulter-first-payment-default` | Carteira Ativa | 83.96% | 77.80% |
| `b) active-new-defaulter-under-mob3` | Carteira Ativa | 86.30% | 85.22% |
| `c) active-new-defaulter` | Carteira Ativa | 79.21% | 82.01% |
| `d) active-stock` | Carteira Ativa | 44.23% | 43.73% |
| `f) ended-new-defaulter` | Carteira Finalizada | 44.00% | 45.75% |
| `g) ended-stock-31-90` | Carteira Finalizada | 4.19% | 5.82% |
| `h) ended-stock-91-180` | Carteira Finalizada | 1.46% | 1.39% |
| `i) ended-stock-181-360` | Carteira Finalizada | 0.61% | 0.66% |
| `j) ended-stock-361-1440` | Carteira Finalizada | 0.23% | 0.32% |
| `k) ended-stock-over1440` | Carteira Finalizada | 0.11% | 0.14% |

For June and July 2026, the same query returns a **null Target** for every bucket above — not a data error, see the "New-segmentation targets only exist from August 2026 onward" nuance above.

## Superset Golden Assets

Shared directly by the requester on 2026-09-18, resolving the previously open "which Superset chart is official" question for this entity:

- **"Carteira Ativa" reference chart** (Net Recovery vs. Target, `portfolio IN (a, b, c, d)`) — slice **63561**.
- **"Carteira Finalizada" reference chart** (Net Recovery vs. Target, `portfolio IN (f, g, h, i, j, k)`) — slice **63573**.

The three previously-found unconfirmed candidates (slices 37840, 39248, 39250) remain unconfirmed and are not cited here — these two new slices are a different, now-confirmed pair of charts specifically for the vs.-Target view by book (active/ended), not necessarily the same chart the earlier candidates referred to.
