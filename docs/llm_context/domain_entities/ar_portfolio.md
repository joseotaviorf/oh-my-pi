# AR Portfolio

## Ownership

**Data Owner:**
- maxsuel.alves@quintoandar.com.br

**Data Steward:**
- maxsuel.alves@quintoandar.com.br

## Overview

- **Objective:** Daily timeline of QuintoAndar's full accounts receivable (AR) invoice portfolio — every invoice in the AR ledger, not just the delinquent-tenant segment tracked elsewhere. Combines the receivables ledger with per-invoice collection classification (when available) to support consolidated AR reporting, recovery-rate tracking, and target/OKR comparison.
- **Asset status / lifecycle:** Production. `fact_ar_portfolio_timeline` is fully rebuilt every run (`CREATE OR REPLACE TABLE`). It has an **execution-order dependency** on T2 Overdue Portfolio (`t2_fact_overdue_portfolio_timeline` must complete first, since this table's classification fields are inherited from it).
- **Typical actions / events:** every AR invoice is expanded (fan-out) across every day of its recovery month (`dt_month_recovery`); payment-sensitive fields switch from an "open" state to their real value once `dt_reference` reaches the payment date.
- **Common metrics:** AR Recovery / % AR Recovery (official — see Key Metrics below); wallet composition by `ar_portfolio`; aging-bucket wallet share; recovery rate vs. target by macro aging bucket.
- **Source systems:** `dw_losses.fact_accounts_receivable` (core AR ledger), `dw_losses.fact_delay`, `dw_public.dim_date`, `datalake_collections_quintoandar.invoice_portfolio`, `datalake_retsuko.invoice`, `sandbox.dw_evictions_cyber_legal`, and `sandbox.t2_fact_overdue_portfolio_timeline` (collection classification source).
- **Related entities:** For the narrower, delinquent-tenant-only collections timeline that supplies this entity's classification fields, see **T2 Overdue Portfolio** (`t2_fact_overdue_portfolio_timeline`). For OKR/target values compared against this entity's recovery rate, see `planning_performance_fact_daily_targets` (documented under Tables below — it currently has **no owner, domain, or tags registered in DataHub**; treat as an open action item, not a documented source).

**Grain:** one row per invoice (`sk_invoice`) per calendar reference date (`dt_reference`), within the invoice's recovery month (`dt_month_recovery`).

## Glossary and Synonyms

- **`ar_portfolio`** → business portfolio classification. Confirmed via live Trino query: 19 values = the 13 lettered buckets inherited from T2 Overdue Portfolio's `portfolio` field (`a`–`m`, when the invoice is under active collection tracking) **plus** 6 fallback categories used only when it is not: `n) Baixa Manual`, `o) Cancelado`, `p) A vencer`, `q) Pago em Dia`, `r) Proprietário`, `s) Não Mapeado`. On the 2026-09-13 snapshot, `q) Pago em Dia` was the single largest bucket (≈R$750M of a ≈R$1.58B total wallet in the "AR 90" macro bucket); `s) Não Mapeado` represented **≈0.45% of total wallet** (R$7.17M of R$1.58B) — a real baseline, not a defined alert threshold (none exists yet; treat as an open action item).
- **`collections_segmentation`** → **newly discovered field, not previously documented.** Cross-referencing its 38 observed values against T2 Overdue Portfolio's `segmentation` (32 values) and `ar_portfolio`'s 6 fallback categories: the two sets match exactly (32 + 6 = 38, with identical row counts per fallback category). **Inferred (needs business confirmation): `collections_segmentation` = the invoice's raw `segmentation` value when under active collection tracking, or the same fallback label used by `ar_portfolio` when not** — i.e., the AR-side equivalent of `segmentation` (fine-grained) the way `ar_portfolio` is the AR-side equivalent of `portfolio` (coarse, lettered).
- **Aging bucket mapping to targets** — `macro_ar_delay_contamined_range` values map to `planning_performance_fact_daily_targets` columns as follows (recovered from the production Superset query, formalized here so it doesn't need to be re-derived from SQL each time):

  | `macro_ar_delay_contamined_range` | Target column |
  |---|---|
  | `a. AR 90` | `ar_1_90` |
  | `b. AR 91-360` | `ar_91_360` |
  | `c. AR acima de 360` | `ar_over_360` |

  **Important:** these target columns store **decimal recovery-rate targets** (e.g., `0.8801` = 88.01%), confirmed via live query — **not** portfolio amount targets. By order-of-magnitude comparison against the same day's wallet, the target appears to be set against the **full** population per macro bucket (including `q) Pago em Dia` / `p) A vencer`), consistent with this entity's scope — but this is a data-based inference, not a confirmation from whoever owns the target table.
- **Near-miss — "Net Recovery"** → belongs to **T2 Overdue Portfolio** (delinquent-tenant-only population); do not resolve tenant Net Recovery questions against this entity.
- **Near-miss — Landlord Net Recovery** → a different metric/table/domain entirely; `r) Proprietário` here only marks landlord-billed invoices within the AR ledger, it is not the landlord recovery metric itself.

## Tables

| You need… | Table | Grain | Mandatory filters/dedup |
|---|---|---|---|
| Full AR ledger daily timeline, wallet, recovery amount, `ar_portfolio` classification | `sandbox.fact_ar_portfolio_timeline` | One row per `sk_invoice` per `dt_reference` | `is_last_business_days = TRUE` when comparing by `business_day` across months; `business_day = mtd` for month-to-date locks |
| Recovery-rate OKR/target by macro aging bucket | `sandbox.planning_performance_fact_daily_targets` | One row per `dt_reference` (rate columns, not amounts) | **Not provided:** owner, refresh cadence, and target-setting process are not registered in DataHub — confirm with whoever owns Planning/Performance target-setting before treating this as authoritative |

## Key Metrics

Use [Official metrics (metric entities)](#official-metrics-metric-entities) below for official AR Recovery / % AR Recovery — do not compute an official OKR number directly from these tables.

### Official metrics (metric entities)

| When you need… | Metric entity |
|---|---|
| AR Recovery, % AR Recovery | `ar_recovery_context.md` |

### Component / exploratory metrics

- **Wallet composition by `ar_portfolio`** — `SUM(invoice_amount)` grouped by `ar_portfolio`, month over month.
- **Wallet share by aging bucket** — `SUM(invoice_amount) / total_invoice_amount_faixa_ar_dt_reference` grouped by `ar_delay_contamined_range` and `ar_portfolio`.
- **Recovery rate vs. target** — `% AR Recovery` (see metric entity) divided by the mapped target column, by `macro_ar_delay_contamined_range`, MTD-locked (`business_day = mtd`).
- **`Não Mapeado` monitoring** — `SUM(invoice_amount)` where `ar_portfolio = 's) Não Mapeado'`, as a share of total wallet; observed baseline ≈0.45% (2026-09-13) — flag unusual increases even without a formal threshold.

## Relationships with other entities

- **AR Portfolio ← T2 Overdue Portfolio** (`t2_fact_overdue_portfolio_timeline`, N:1 per invoice per date): `portfolio`, `debtor_type`, `advisory`, `contract_status`, `delay_contamined_range` are inherited via `LEFT JOIN` on matching `dt_reference`, only for invoices under active collection tracking (null otherwise, handled by the `ar_portfolio` fallback logic). Execution order: T2 Overdue Portfolio must complete first.
- **AR Portfolio ↔ `planning_performance_fact_daily_targets`**: joined by `dt_reference` (and sometimes `business_day`) to compare `% AR Recovery` against a rate target per macro aging bucket. This target table carries no DataHub metadata (no owner, domain, or tags) — treat any join to it as provisional pending ownership confirmation.
- **AR Portfolio → Eviction status source** (`sandbox.dw_evictions_cyber_legal`, referenced not joined-in-full): `closing_month_evic_status` checks whether the invoice's **fixed** `dt_closing` (not `dt_reference`) falls inside an active eviction case window — a different date basis than T2 Overdue Portfolio's `status_evic`.

## Dos and don'ts

**Do:**
- Use the full invoice population — `ar_portfolio` and `collections_segmentation` already encode whether an invoice is under active collection or one of the six fallback states; no additional canonical filter is needed for AR-wide analysis.
- Apply `is_last_business_days = TRUE` and `business_day = mtd` for month-to-date and cross-month comparisons.
- Use the `macro_ar_delay_contamined_range` → target-column mapping table above instead of re-deriving it from the `CASE` logic in a production query.
- Remember target values in `planning_performance_fact_daily_targets` are **decimal rates**, not amounts.
- Keep `ar_delay_contamined_range` / `macro_ar_delay_contamined_range` (AR-specific bucket scheme) separate from `delay_contamined_range` (inherited T2 bucket scheme, null when not under active collection).

**Don't:**
- Don't sum `invoice_amount` / `net_recovered` across multiple `dt_reference` values, or group by `business_day`, without collapsing the daily fan-out first.
- Don't treat `ar_portfolio = 's) Não Mapeado'` as a normal category — it signals an unmapped gap (baseline ≈0.45% of wallet; investigate meaningful increases).
- Don't assume `planning_performance_fact_daily_targets` values are portfolio amounts — they are recovery-rate targets.
- Don't join to `planning_performance_fact_daily_targets` and present the result as an "official" comparison without flagging that the source table's ownership/methodology is unconfirmed.
- Don't confuse `collections_segmentation` with `ar_portfolio` — one is the fine-grained raw segment (inferred), the other the coarse lettered/fallback rollup (confirmed).

## Golden Queries

**Wallet share (`% Share`) by aging bucket and `ar_portfolio`**, MTD-locked, trailing 13 months. From production Superset chart.

```sql
SELECT
    date_trunc('day', CAST(dt_month_start AS TIMESTAMP)) AS dt_month_start,
    business_day,
    ar_delay_contamined_range,
    ar_portfolio,
    SUM(invoice_amount) / MAX(total_invoice_amount_faixa_ar_dt_reference) AS "% Share"
FROM (
    SELECT *
    FROM sandbox.fact_ar_portfolio_timeline
    WHERE dt_month_start >= CURRENT_DATE - INTERVAL '13' MONTH
) AS virtual_table
WHERE is_last_business_days = TRUE
  AND business_day = mtd
GROUP BY date_trunc('day', CAST(dt_month_start AS TIMESTAMP)), business_day, ar_delay_contamined_range, ar_portfolio
ORDER BY "% Share" DESC
```

**Wallet composition by `ar_portfolio`**, month over month, trailing 12 months. From production Superset chart.

```sql
SELECT
    date_trunc('month', CAST(dt_month_start AS TIMESTAMP)) AS dt_month_start,
    ar_portfolio,
    SUM(invoice_amount) AS "Carteira"
FROM (
    SELECT *
    FROM sandbox.fact_ar_portfolio_timeline
    WHERE dt_month_start >= CURRENT_DATE - INTERVAL '13' MONTH
) AS virtual_table
WHERE is_last_business_days = TRUE
  AND business_day = mtd
  AND date_trunc('month', dt_reference) BETWEEN date_add('month', -12, date_trunc('month', current_date)) AND date_add('day', -1, current_date)
GROUP BY date_trunc('month', CAST(dt_month_start AS TIMESTAMP)), ar_portfolio
ORDER BY "Carteira" DESC
```

**Recovery rate vs. target, by macro aging bucket, month over month** — multi-month trend variant (the single-month production version only covers the current month; this adds `LAG` for a reusable trend reference). Validated in Trino (dry run structure matches the validated single-month version; see `ar_recovery_context.md` Golden Queries for the base CTE chain).

```sql
WITH ar_timeline_data AS (
    SELECT
        dt_reference, dt_month_start, dt_month_end, business_day,
        macro_ar_delay_contamined_range,
        SUM(net_recovered) AS net_recovered_amount,
        SUM(invoice_amount) AS invoice_amount
    FROM sandbox.fact_ar_portfolio_timeline
    WHERE is_last_business_days = TRUE
    GROUP BY 1, 2, 3, 4, 5
),
targets_data AS (
    SELECT dt_reference, ar_1_90, ar_91_360, ar_over_360
    FROM sandbox.planning_performance_fact_daily_targets
),
aux_mtd AS (
    SELECT DISTINCT month_start, total_working_days_in_month_fintech,
        (SELECT working_days_in_month_fintech FROM dw_public.dim_date
         WHERE date = (SELECT MAX(dt_reference) FROM ar_timeline_data LIMIT 1)) AS du_atual
    FROM dw_public.dim_date
),
aux_mtd_data AS (
    SELECT month_start,
        CASE WHEN du_atual > total_working_days_in_month_fintech THEN total_working_days_in_month_fintech ELSE du_atual END AS mtd
    FROM aux_mtd
)
SELECT
    ar.macro_ar_delay_contamined_range AS "Faixa AR",
    date_trunc('month', ar.dt_month_end) AS mes,
    ar.net_recovered_amount * 1.0000 / ar.invoice_amount AS pct_ar_recovery,
    CASE ar.macro_ar_delay_contamined_range
        WHEN 'a. AR 90' THEN t.ar_1_90
        WHEN 'b. AR 91-360' THEN t.ar_91_360
        WHEN 'c. AR acima de 360' THEN t.ar_over_360
    END AS target,
    LAG(ar.net_recovered_amount * 1.0000 / ar.invoice_amount, 1) OVER (
        PARTITION BY ar.macro_ar_delay_contamined_range ORDER BY ar.dt_month_start
    ) AS pct_ar_recovery_l1m
FROM ar_timeline_data AS ar
LEFT JOIN aux_mtd_data AS mtd_d ON ar.dt_month_start = mtd_d.month_start
LEFT JOIN targets_data AS t ON ar.dt_reference = t.dt_reference
WHERE ar.business_day = mtd_d.mtd
  AND ar.dt_reference >= date_add('month', -13, date_trunc('month', current_date))
ORDER BY "Faixa AR", mes DESC
```
