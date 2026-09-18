# AR Recovery

## Ownership

**Data Owner:**
- maxsuel.alves@quintoandar.com.br

**Data Steward:**
- maxsuel.alves@quintoandar.com.br

## Overview

**AR Recovery** measures recovery performance over QuintoAndar's full accounts receivable (AR) invoice portfolio. This entity covers two closely related official metrics: **AR Recovery** (the absolute monetary amount recovered) and **% AR Recovery** (that amount expressed as a percentage of the total invoiced amount in the same population). Which one applies depends on the question shape: a value question resolves to **AR Recovery**; a rate question resolves to **% AR Recovery**, which requires comparing recovered amount against the invoiced-amount base.

Unlike collections-specific metrics scoped to a delinquent sub-segment, AR Recovery spans the entire AR invoice population tracked in the source timeline — including invoices under active tenant collection tracking, landlord-billed invoices, cancelled invoices, invoices paid on time, and invoices not yet due.

## Related Domain Entities

- **AR Portfolio** (`ar_portfolio_context.md`) — full field glossary (`ar_portfolio`, `collections_segmentation`), table routing, and exploratory/component metrics for `sandbox.fact_ar_portfolio_timeline`. URN: `urn:li:dataset:(urn:li:dataPlatform:trino,hive.sandbox.fact_ar_portfolio_timeline,PROD)`
- **T2 Overdue Portfolio** (`t2_overdue_portfolio_context.md`) — upstream source of this entity's inherited classification fields (`portfolio`, `advisory`, `debtor_type`, `contract_status`, `delay_contamined_range`). URN: `urn:li:dataset:(urn:li:dataPlatform:trino,hive.sandbox.t2_fact_overdue_portfolio_timeline,PROD)`

## Catalog

| Metric | Type |
| :---- | :---- |
| AR Recovery | OKR |
| % AR Recovery | OKR |

## Glossary and Synonyms

- **AR Recovery** → this entity — the absolute recovered-amount member metric
- **% AR Recovery** → this entity — the percentage member metric

## Scope

**Included**: all invoices in `sandbox.fact_ar_portfolio_timeline` — the full AR ledger population, spanning invoices under active tenant collection tracking, landlord-billed invoices (`ar_portfolio` fallback value `r) Proprietário`), cancelled invoices, invoices paid on time, and invoices not yet due.

**Excluded**: not applicable — no population-narrowing filter is part of this metric's definition. Note this entity is distinct from tenant collections **Net Recovery**, which is scoped only to the directly-collectable delinquent segment of a different table (`t2_fact_overdue_portfolio_timeline`); the two are not interchangeable.

## Calculation

The correct calculation is:

```
AR Recovery = SUM(net_recovered)
% AR Recovery = SUM(net_recovered) / SUM(invoice_amount)
```

`net_recovered` and `invoice_amount` are read per invoice, per reference date, from the AR portfolio timeline.

The source table carries one row per invoice per calendar day for as long as the invoice appears in its recovery-month timeline. Summing `net_recovered` / `invoice_amount` across a date range, or grouping by `business_day` without first collapsing the daily fan-out, multiplies the same invoice's balance across every day it appears — inflating both the numerator and the denominator.

### Canonical Filter

Not applicable — the metric is calculated over the full `sandbox.fact_ar_portfolio_timeline` population, with no restrictive filter equivalent to tenant Net Recovery's `collectable_delinquent_portfolio = TRUE`.

### Nuances

No external weight or parameter table — both metrics are direct `SUM` aggregations.

- **Business-day alignment**: to compare the same day-of-month position across different months, group by `business_day` and additionally filter `is_last_business_days = TRUE` — calendar dates that share a business-day ordinal (e.g., a weekend or holiday carrying the prior business day's count) would otherwise duplicate the balance into that ordinal.
- **Date-based views**: when slicing directly by `dt_reference` (a single calendar date), `is_last_business_days` is not needed — the date is already a grain key.
- **MTD lock**: the `mtd` field holds the number of business days elapsed in the most recent month present in the table (capped to each month's own total working days). Filtering `business_day = mtd` locks a comparison to the same month-to-date position across historical months.
- **Two coexisting aging-bucket schemes**: `ar_delay_contamined_range` / `macro_ar_delay_contamined_range` are AR-specific aging buckets computed for every invoice; `delay_contamined_range` is a different bucket scheme inherited from active tenant collection tracking (null when the invoice is not under active collection). Do not mix the two.
- **`ar_portfolio` as the primary business segmentation**: combines the invoice's active collection classification (when present) with fallback categories when it isn't — landlord-billed (`r) Proprietário`), cancelled (`o) Cancelado`), manual write-off (`n) Baixa Manual`), paid on time (`q) Pago em Dia`), not yet due (`p) A vencer`), or unmapped (`s) Não Mapeado`). The unmapped fallback signals an unexpected gap and should be monitored, not treated as a normal category (observed baseline ≈0.45% of total wallet). Full value dictionary (19 values) and the newly-discovered `collections_segmentation` field: see `ar_portfolio_context.md`.
- **Eviction status field**: `closing_month_evic_status` (`EVICTION` / `EM COBRANCA`), calculated from the invoice's fixed `dt_closing` — it does not vary across the timeline the way a reference-date-driven field would.
- **Recovery channel as payment-type breakdown**: `recovery_channel` holds the channel through which the invoice was recovered, populated only once paid.
- **Decimal division**: force decimal division in the numerator (e.g., `* 1.0000`) to avoid integer-division truncation in Trino.
- **Rolling window convention**: production views commonly scope to a ~12–13 month rolling window because the source table is large/costly to scan fully — a performance convention, not a fixed business rule.
- **Upstream execution dependency**: `sandbox.fact_ar_portfolio_timeline` inherits its active-collection classification from `t2_fact_overdue_portfolio_timeline` and depends on that table's run completing first.
- **Target/OKR comparison views** additionally join `sandbox.planning_performance_fact_daily_targets` (by `dt_reference` and `business_day`) to compute Tgt MTD / Tgt FM / vs Tgt / MoM / YoY columns. Confirmed live in DataHub: this table has **no owner, domain, or tags registered** — treat its ownership and target-setting methodology as an open action item, not a documented fact. Confirmed live in Trino: its `ar_1_90`/`ar_91_360`/`ar_over_360` columns are **decimal recovery-rate targets** (e.g. `0.8801` = 88.01%), not portfolio amounts. The `macro_ar_delay_contamined_range` → target-column mapping is formalized in `ar_portfolio_context.md` (Glossary and Synonyms) instead of being re-derived from the `CASE` logic each time.

**Fallback**: not applicable — no parameter table is involved in the core calculation.

## Dos and Don'ts

**Do:**

- Use the full invoice population — no canonical filter is required unless a specific narrower analysis is intended.
- Apply `is_last_business_days = TRUE` whenever grouping or comparing by `business_day`.
- Use `business_day = mtd` for month-to-date comparisons across months.
- Force decimal division to avoid truncation.
- Keep `ar_delay_contamined_range` / `macro_ar_delay_contamined_range` and `delay_contamined_range` separate — they are different bucket schemes.

**Don't:**

- Don't sum `net_recovered` / `invoice_amount` across multiple `dt_reference` values, or group by `business_day`, without first collapsing the daily fan-out — it double- or triple-counts the same invoice.
- Don't treat the unmapped fallback (`ar_portfolio` value `s) Não Mapeado`) as a normal category — it signals an unmapped gap.
- Don't confuse this entity with tenant collections **Net Recovery** — different source table, different population scope.

## Golden Queries

Overall **AR Recovery** and **% AR Recovery** as of a single point-in-time reference date. No business-day dedup is needed here since `dt_reference` is already a grain key.

```sql
SELECT
    SUM(net_recovered) AS ar_recovery,
    SUM(net_recovered) * 1.0000 / SUM(invoice_amount) AS pct_ar_recovery
FROM sandbox.fact_ar_portfolio_timeline
WHERE dt_reference = DATE '2026-09-07' -- replace with the desired reference date
```

Month-end wallet (**Wallet**) and **AR Recovery** absolute amount, over a trailing 13-month window, locked to each month's MTD business day.

```sql
SELECT
    date_trunc('month', CAST(dt_month_end AS TIMESTAMP)) AS dt_month_end,
    SUM(invoice_amount) AS "Wallet",
    SUM(net_recovered) AS "AR Recovery"
FROM (
    SELECT *
    FROM sandbox.fact_ar_portfolio_timeline
    WHERE dt_month_start >= CURRENT_DATE - INTERVAL '13' MONTH
) AS virtual_table
WHERE is_last_business_days = TRUE
  AND business_day = mtd
  AND date_trunc('month', dt_reference) BETWEEN date_add('month', -13, date_trunc('month', current_date)) AND date_add('day', -1, current_date)
GROUP BY date_trunc('month', CAST(dt_month_end AS TIMESTAMP))
ORDER BY "Wallet" DESC
```

Cumulative **% AR Recovery** by business-day position within the month, over a trailing window — enables comparing the same day-of-month point across different months.

```sql
SELECT
    business_day,
    DATE_FORMAT(dt_month_start, '%y-%m') AS "Month",
    SUM(net_recovered) * 1.0000 / SUM(invoice_amount) AS "% AR Recovery"
FROM (
    SELECT *
    FROM sandbox.fact_ar_portfolio_timeline
    WHERE dt_month_start >= CURRENT_DATE - INTERVAL '13' MONTH
) AS virtual_table
WHERE is_last_business_days = TRUE
  AND date_trunc('month', dt_reference) BETWEEN date_add('month', -3, date_trunc('month', current_date)) AND date_add('day', -1, current_date)
GROUP BY business_day, DATE_FORMAT(dt_month_start, '%y-%m')
ORDER BY "% AR Recovery" DESC
```

**% AR Recovery vs. target, by macro aging bucket, month over month**, MTD-locked — see `ar_portfolio_context.md` (Golden Queries) for the full query, since it mixes in the OKR/target comparison rather than computing AR Recovery alone. The aging-bucket-to-target-column mapping is documented there too.

Wallet share and wallet composition breakdowns by `ar_portfolio` / aging bucket — also moved to `ar_portfolio_context.md` (Golden Queries), since they are exploratory/component metrics on the domain's tables rather than direct reproductions of the AR Recovery formula.

## Superset Golden Assets

Confirmed live via DataHub chart search (names and URLs, not just slice IDs):

- **AR Macro Pannel MTD** `[Fintech][P&P]` — https://superset.data.quintoandar.com.br/explore/?slice_id=54603 — URN: `urn:li:chart:(superset,chart.54603)`. Note: "Pannel" (double *n*) is the exact chart name as registered in DataHub (`properties.name`), re-confirmed live — not a typo introduced in this documentation. If the intended word is "Panel," that correction belongs in the source chart's own name, not here.
- **AR Result MTD** `[Fintech][P&P]` — https://superset.data.quintoandar.com.br/explore/?slice_id=54728 — URN: `urn:li:chart:(superset,chart.54728)`
- **% Net Recovered AR T2 MTD** `[Fintech][P&P]` — https://superset.data.quintoandar.com.br/explore/?slice_id=54428 — URN: `urn:li:chart:(superset,chart.54428)`
- **Share Collec Portfolio AR T2 MTD** `[Fintech][P&P]` — https://superset.data.quintoandar.com.br/explore/?slice_id=54729 — URN: `urn:li:chart:(superset,chart.54729)`

Two additional charts referenced during analysis (micro aging bucket breakdown; wallet share by `ar_delay_contamined_range`/`ar_portfolio`) were provided without an identifiable slice ID (**Not provided**).
