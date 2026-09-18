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
```

**Warning**: Omitting this filter includes invoices under an active negotiation (the regularized portfolio), which are not part of the official Net Recovery universe and distort the rate.

### Nuances

No external weight or parameter table — both metrics are direct `SUM` aggregations.

- **Business-day alignment**: to compare the same day-of-month position across different months, group by `business_day` and additionally filter `is_last_business_days = TRUE` — calendar dates that share a business-day ordinal (e.g., a weekend or holiday carrying the prior business day's count) would otherwise duplicate the balance into that ordinal.
- **Date-based views**: when slicing directly by `dt_reference` (a single calendar date), `is_last_business_days` is not needed — the date is already a grain key, so each invoice contributes exactly one row.
- **Month-end snapshot**: add `dt_reference = dt_month_end` to get the true closing position for a month, rather than just the last business day.
- **Recovery-method decomposition**: breaking `% Net Recovery` down by `recovery_method` (categories `b) Original Payment` through `f) Written-down w/o Negotiation`) sums back to the total; `a) Open` never contributes, since its `net_recovered_amount` is always zero.
- **Decimal division**: force decimal division in the numerator (e.g., `* 1.0000`) to avoid integer-division truncation in Trino.
- **Rolling window convention**: production views commonly scope to a ~12–13 month rolling window because the source table is large/costly to scan fully — this is a performance convention, not a fixed business rule, and the window can be adjusted per analysis need.
- **Cutting by `advisory` or `segmentation`**: both are native fields on this table (not a join to another domain) — full value dictionaries, the external/internal advisory split, and a Simpson's-paradox warning about comparing recovery rate across `advisory` without controlling for `segmentation`/aging are documented in `t2_overdue_portfolio_context.md` (Glossary and Synonyms / Dos and Don'ts), along with two ready-to-use monthly trend Golden Queries for each cut.

**Fallback**: not applicable — no parameter table is involved.

## Dos and Don'ts

**Do:**

- Always apply `collectable_delinquent_portfolio = TRUE`.
- Apply `is_last_business_days = TRUE` whenever grouping or comparing by `business_day`.
- Add `dt_reference = dt_month_end` for month-end closing views.
- Force decimal division to avoid truncation.

**Don't:**

- Don't sum `due_amount` / `net_recovered_amount` across multiple `dt_reference` values, or group by `business_day`, without first collapsing the daily fan-out — it double- or triple-counts the same invoice.
- Don't include invoices under an active negotiation — they are out of scope for this metric.
- Don't confuse this entity with landlord (Proprietário) Net Recovery — different source table and domain.

## Golden Queries

Overall **Net Recovery** and **% Net Recovery** as of a single point-in-time reference date. No business-day dedup is needed here since `dt_reference` is already a grain key.

```sql
SELECT
    SUM(net_recovered_amount) AS net_recovery,
    SUM(net_recovered_amount) * 1.0000 / SUM(due_amount) AS pct_net_recovery
FROM sandbox.t2_fact_overdue_portfolio_timeline
WHERE collectable_delinquent_portfolio = TRUE
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
GROUP BY business_day, date_trunc('day', CAST(dt_month_end AS TIMESTAMP))
ORDER BY SUM(CASE WHEN recovery_method = 'b) Original Payment' THEN net_recovered_amount END) * 1.000 / SUM(due_amount) ASC
LIMIT 10000
```
