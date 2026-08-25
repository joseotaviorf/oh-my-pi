# Recovery — Collections (For-Rent Tenants)

## Overview

This document covers **recovery analytics for tenants on the For-Rent (FR) product**. Recovery measures how much overdue debt is collected from defaulting customers, and how that collection performance evolves over time.

**Scope:** Tenants in For-Rent units only. Recovery analytics for **landlords on FR** or **buyers on For-Sale (FS)** are out of scope here and will be documented separately.

Why this scope matters: ~95% of what we collect is **rental** debt, and rentals are emitted monthly. That cadence justifies a **monthly wallet view** as the default reporting unit, but the same math generalizes to any open-ended date range.

Before answering any recovery question, decide which lens applies:

| View | What it answers | When to use |
|------|-----------------|-------------|
| **Snapshot** | Given the wallet on day X (every defaulting customer at that moment), how much had been recovered N days later (e.g. 10, 15, 20 days after the snapshot)? | Forecasting roll-down on a frozen wallet; vintage / cohort follow-up of a single closing date. |
| **Cohort / accumulated (MTD)** | For a target month, how much of all the **overdue debt that came to be during the month** was recovered **within the month**? | Monthly performance against targets, MTD comparisons, "what is April's recovery rate today?" type questions. |

> **Important — why naive ratios mislead in cohort view.** If you simply compute `recovered_in_month / due_in_month_at_month_end`, the rate looks artificially low. Once an invoice is paid, it leaves the open wallet, so by month end the denominator only contains what was **not** recovered. You must **accumulate** both due and recovered amounts across all defaulting events that occur within the month — only then does the ratio reflect true monthly recovery.

A contract can change segment **inside a single month** (e.g. it ends mid-month, moves from `active-*` to `ended-*`). To attribute recovery correctly by segment you have to:

- **Double-count** the contract on a per-segment basis (one denominator per segment it lived in), and
- Move the recovery to the segment in which the invoice was actually paid (or keep building denominator on the new segment until paid).

This is why the queries below partition wallet/recovery by `(sk_invoice, dt_reference)` rather than by contract alone — the segmentation is a **daily property**, not a monthly one.

## Synonyms

| Term | Meaning |
|------|---------|
| **Recovery** | Money collected from previously overdue invoices |
| **Recovery rate (RR)** | `recovered_amount / due_amount` over a defined wallet and time range |
| **MTD recovery** | Month-to-date cohort recovery (accumulated due vs accumulated recovered within the month) |
| **Snapshot recovery** | Recovery measured against a frozen wallet from a fixed reference date |
| **Wallet** | Set of overdue invoices being tracked |
| **DT2 / Delay-T2** | Invoice delay methodology that contaminates with deal/negotiation status (operational standard for recovery) |
| **Pipe / `dt_pipe`** | The "billing pipe" reference date — the operational anchor used to align month-over-month comparisons |
| **MoB** | Month-over-Month offset (0 = current month, 1 = previous month, …) |
| **Hyper / Macro / Clustered / Basic** | Four-tier hierarchy of segmentation granularity (see Segmentation Levels) |
| **Chargehub** | Domain system that receives segment data from the Data Lake and applies operational refinements |
| **Cyber** | Downstream legal/operational system that consumes finalized segments from Chargehub |
| **PoP** | Probability of Payment (Very High / High / Medium / Low) |

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Daily **invoice** wallet (per-invoice timeline of due, recovered, delay T1/T2/T3, payment status) | `dw_collections_segmentation.fact_invoice_wallet_timeline` |
| Daily **contract** wallet (rollups, recovery channels, `dt_pipe`, comms) | `dw_collections_segmentation.fact_contract_wallet_timeline` |
| Official **segmentation** features per contract-day (data-lake segmentation, macro/hyper) | `dw_collections_segmentation.fact_contract_features_timeline` |
| Live operational segment allocation (Chargehub audiences) | `datalake_debt_recovery.segmentation_distribution` |
| Materialized monthly recovery, Chargehub audiences | `metric_fintech.daily_recovery_chargehub_audiences` |
| Materialized monthly recovery, **basic** segmentation | `metric_fintech.daily_recovery_segmentation` |
| Materialized monthly recovery, **clustered** segmentation | `metric_fintech.daily_recovery_segmentation_clustered` |
| Materialized monthly recovery, **macro** segmentation | `metric_fintech.daily_recovery_macro_segmentation` |
| Materialized monthly recovery, **hyper** segmentation | `metric_fintech.daily_recovery_hyper_segmentation` |
| Calendar / business-day flags (used to align MTD comparisons) | `dw_public.dim_date` |

> Use the **metric_fintech.daily_recovery_*** tables whenever possible — they already encode the cohort accumulation logic, segment alignment, and `n_business_days_since_pipe` for cross-month parity.

### The `dw_collections_segmentation` building blocks

These three tables are the foundation. Every recovery question can be answered by combining them.

#### `fact_invoice_wallet_timeline`

Daily **invoice** grain: one row **per invoice per day** from creation (or first appearance in wallet) until payment / write-down.

| Topic | Fields |
|-------|--------|
| Keys | `sk_invoice`, `sk_contract`, `dt_reference`, `dt_begin`, `dt_paid` |
| Amounts | `due_amount` (sign convention: stored negative; use `ABS(due_amount)`), `recovered_amount` |
| Delay | `invoice_delay_t1`, `invoice_delay_t2`, `invoice_delay_t3` |
| Status | `payment_status` |
| Channels | recovery-channel and bill-item flags inherited from operational sources |

#### `fact_contract_wallet_timeline`

Daily **contract** grain: one row per contract per day from first invoice emission until last payment (ended) or current date (active). Aggregates the invoice wallet up to the contract.

| Topic | Fields |
|-------|--------|
| Keys | `sk_contract`, `dt_reference` |
| Pipe / cohort anchor | **`dt_pipe`** — operational reference date used to align MTD comparisons across months |
| Wallet rollups | total wallet, max delays, counts of overdue invoices, comms / promessas / app events, eviction flags |

### `fact_contract_features_timeline`

The **official segmentation** layer that drives operational strategy and communications.

| Field | Meaning |
|-------|---------|
| `segmentation` | Frozen (stable) segmentation that guides negotiation strategy |
| `macro_segmentation` | Macro view (no PoP breakdown) |
| `tree_class` | Decision-tree class once a contract enters a stable segment |
| `prob_payment` | Frozen Probability of Payment |
| `t1_delay_bucket`, `t2_delay_bucket` | Delay buckets aligned with T1 / T2 methodologies |

> **Always include the partition guard** when joining these tables to avoid full scans:
> `MAKE_DATE(year, month, day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS`.

### Data flow & system sync

Segmentation data flows sequentially through three systems. Segment definitions are **identical** across them, but brief sync delays are normal.

1. **Data Lake (analytical)** — base segments are calculated and created here.
2. **Chargehub (domain)** — receives segments from the Data Lake and applies domain-level refinements (audiences).
3. **Cyber** — consumes the finalized segment data directly from Chargehub.

If you need the **live operational view** (what's currently being acted on), use Chargehub audiences (`datalake_debt_recovery.segmentation_distribution`). If you need the **stable analytical view** (what segmented the wallet on a given day), use `dw_collections_segmentation.fact_contract_features_timeline`.

### Segmentation levels

Four-tier hierarchy from most granular to highest-level summary:

| Level | What it strips | Example use |
|-------|----------------|-------------|
| **Basic** | — (most granular: includes Early/Late timing and PoP) | Operational deep-dive, audience targeting |
| **Clustered** | Removes the **Early / Late** timing dependency | Operational segments without timing dimension |
| **Macro** | Also removes the **PoP** breakdown (Very High / High / Medium / Low) | Strategic / portfolio reporting |
| **Hyper** | Highest-level: collapses everything into **Active / Ended / Evictions** | Executive summary, contract-status splits |

Each level has its own materialized recovery table under `metric_fintech.daily_recovery_*`.

## Relationships with other entities

- **Tenants on FR** is the universe — joins to `dw_rent.dim_contract` for contract attributes.
- **Operational collections actions** live in `dw_collection_recovery_quintoandar` (see `collections.md`); join via `sk_contract` for touches / negotiations.
- **Provisioned losses (PDD)** live in `dw_losses` (see `losses.md`); the recovery measured here covers operational collections **before and around** PDD inclusion.
- **Payments** that fulfill recovery are tracked in `dw_payments_platform` (see `payments.md`); the `recovered_amount` column already reflects settled cash.
- **Evictions** flagged on `fact_contract_wallet_timeline.is_evictions` align with `dw_evictions.fact_evictions`.

## Dos and don'ts

**Do:**

- Choose the right view first: **snapshot** (frozen wallet, future recovery) vs **cohort/MTD** (accumulated within the month).
- For monthly performance, **always accumulate** both `due_amount` and `recovered_amount` across the whole month — never compare end-of-month wallet to end-of-month recoveries.
- Filter `invoice_delay_t2 > 0` to focus on the **operational recovery universe** (DT2 is the standard for collections KPIs on tenants).
- Use **`ABS(due_amount)`** when summing — the column is stored with negative sign in `fact_invoice_wallet_timeline`.
- Always include the 6-month partition guard `MAKE_DATE(year, month, day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS` to avoid full-table scans.
- For MTD comparisons across months, align by **`n_business_days_since_pipe`** (preferred), or by running days, depending on the operational question — see `get_parity_table` below.
- Exclude `segmentation IN ('active-current', 'ended-current')` and require `wallet > 0` when measuring recovery — these contracts are not in the recovery universe.
- Use `LAST_VALUE(... TRUE) OVER (...)` to **propagate / back-fill** segment and amount features forward in time once an invoice leaves the daily timeline (it disappears the day it is paid). The "any range" golden query shows the pattern.

**Don't:**

- Don't mix the two segmentation sources (`fact_contract_features_timeline.segmentation` vs Chargehub `audience_name`) without being explicit — they are aligned but **not identical** at every timestamp due to system sync delay.
- Don't compute recovery using only the end-of-month wallet — the denominator collapses as invoices are paid.
- Don't compare two months by raw calendar day — MTD recovery is sensitive to the **business-day position relative to `dt_pipe`**. Use `n_business_days_since_pipe` parity (or running-day parity if your business question demands it).
- Don't extend these definitions to **landlords** or **For-Sale buyers** — they have their own data models and recovery semantics.
- Don't deduplicate `datalake_debt_recovery.segmentation_distribution` by contract alone — partition by `(id_contract, dt_last_appearance)` and order by `(ts_entered_segment DESC, ts_entered_audience DESC)`.

## Golden queries

### 1. Materialized monthly recovery (use first)

For most questions, **start here** — these tables already encode cohort accumulation and business-day alignment.

```sql
SELECT *
FROM metric_fintech.daily_recovery_hyper_segmentation
-- or daily_recovery_macro_segmentation
-- or daily_recovery_segmentation
-- or daily_recovery_segmentation_clustered
-- or daily_recovery_chargehub_audiences
WHERE dt_month_ref = DATE_TRUNC('month', CURRENT_DATE);
```

Each row gives you, per `segment` × `dt_reference`:

| Column family | Examples |
|---------------|----------|
| Cohort accumulators | `n_contracts_acc`, `n_invoices_DT2_acc`, `recovered_invoices_DT2_acc`, `due_amount_DT2_acc`, `recovered_amount_DT2_acc`, `recovery_rate_amount_t2` |
| At-reference snapshots | `n_contracts_at_reference`, `n_invoices_DT2_at_reference`, `due_amount_DT2_at_reference` |
| Business-day alignment | `rn_business_day`, `n_business_days_since_pipe`, `days_to_pipe`, `is_brz_fintech_business_day`, `next_brz_fintech_business_day` |
| Period anchors | `dt_month_ref`, `dt_pipe`, `dt_reference` |

### 2. Build the materialized recovery from raw tables (segmentation example)

The query the four `metric_fintech.daily_recovery_*` segmentation tables are built from. Swap `cft.segmentation` for `cft.macro_segmentation` (macro), or use the **hyper** mapping (`active`/`ended`/`evictions`) for the hyper version. The Chargehub-audiences variant uses `datalake_debt_recovery.segmentation_distribution.audience_name` instead of `cft.segmentation` (see Query 3).

```sql
WITH invoice_month_boundaries AS (
    SELECT
        DATE_TRUNC('month', iwt.dt_reference) AS month_ref,
        cft.segmentation,
        iwt.sk_invoice,
        FIRST(cwt.dt_pipe) AS dt_pipe,
        FIRST(iwt.sk_contract) AS sk_contract,
        MIN(iwt.dt_reference) AS dt_min_view,
        MAX(iwt.dt_reference) AS dt_max_view,
        MAX(iwt.due_amount) AS due_amount,
        MAX(iwt.recovered_amount) AS recovered_amount,
        MAX(iwt.invoice_delay_t2) AS invoice_delay_t2
    FROM dw_collections_segmentation.fact_invoice_wallet_timeline AS iwt
    LEFT JOIN dw_collections_segmentation.fact_contract_wallet_timeline AS cwt
        ON cwt.dt_reference = iwt.dt_reference
        AND cwt.sk_contract = iwt.sk_contract
        AND MAKE_DATE(cwt.year, cwt.month, cwt.day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
    LEFT JOIN dw_collections_segmentation.fact_contract_features_timeline AS cft
        ON cft.dt_reference = iwt.dt_reference
        AND cft.sk_contract = iwt.sk_contract
        AND MAKE_DATE(cft.year, cft.month, cft.day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
    WHERE MAKE_DATE(iwt.year, iwt.month, iwt.day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND cft.segmentation NOT IN ('active-current', 'ended-current')
        AND cwt.wallet > 0
    GROUP BY 1, 2, 3
),
daily_accumulation AS (
    SELECT
        dd.date AS dt_reference,
        imb.segmentation AS segment,
        FIRST(imb.dt_pipe) AS dt_pipe,
        COUNT(DISTINCT
            CASE WHEN COALESCE(cft.segmentation, 'Unsegmented') = imb.segmentation
                 THEN iwt.sk_contract END
        ) AS n_contracts_at_reference,
        COUNT(DISTINCT imb.sk_contract) AS n_contracts_acc,
        COUNT(DISTINCT
            CASE WHEN COALESCE(cft.segmentation, 'Unsegmented') = imb.segmentation
                  AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice END
        ) AS n_invoices_DT2_at_reference,
        COUNT(DISTINCT
            CASE
                WHEN dd.date <= imb.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice
                WHEN dd.date >  imb.dt_max_view AND imb.invoice_delay_t2 > 0 THEN imb.sk_invoice
            END
        ) AS n_invoices_DT2_acc,
        COUNT(DISTINCT
            CASE
                WHEN dd.date <= imb.dt_max_view
                     AND iwt.recovered_amount > 0 AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice
                WHEN dd.date >  imb.dt_max_view
                     AND imb.recovered_amount > 0 AND imb.invoice_delay_t2 > 0 THEN imb.sk_invoice
            END
        ) AS recovered_invoices_DT2_acc,
        SUM(
            CASE WHEN COALESCE(cft.segmentation, 'Unsegmented') = imb.segmentation
                  AND iwt.invoice_delay_t2 > 0 THEN ABS(imb.due_amount) END
        ) AS due_amount_DT2_at_reference,
        SUM(
            CASE
                WHEN dd.date <= imb.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN ABS(iwt.due_amount)
                WHEN dd.date >  imb.dt_max_view AND imb.invoice_delay_t2 > 0 THEN ABS(imb.due_amount)
            END
        ) AS due_amount_DT2_acc,
        SUM(
            CASE
                WHEN dd.date <= imb.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN iwt.recovered_amount
                WHEN dd.date >  imb.dt_max_view AND imb.invoice_delay_t2 > 0 THEN imb.recovered_amount
            END
        ) AS recovered_amount_DT2_acc
    FROM dw_public.dim_date AS dd
    LEFT JOIN invoice_month_boundaries AS imb
        ON dd.date >= imb.dt_min_view
        AND dd.month_start = imb.month_ref
    LEFT JOIN dw_collections_segmentation.fact_invoice_wallet_timeline AS iwt
        ON iwt.dt_reference = dd.date
        AND iwt.sk_invoice = imb.sk_invoice
        AND MAKE_DATE(iwt.year, iwt.month, iwt.day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
    LEFT JOIN dw_collections_segmentation.fact_contract_features_timeline AS cft
        ON cft.dt_reference = iwt.dt_reference
        AND cft.sk_contract = iwt.sk_contract
        AND MAKE_DATE(cft.year, cft.month, cft.day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
    WHERE dd.month_start >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND dd.date <= CURRENT_DATE
    GROUP BY 1, 2
),
business_day_context AS (
    SELECT
        da.segment,
        DATE_DIFF(da.dt_reference, da.dt_pipe) AS days_to_pipe,
        COUNT(
            CASE WHEN da.dt_reference >= da.dt_pipe AND dd.is_brz_fintech_business_day
                 THEN da.dt_reference END
        ) OVER (
            PARTITION BY da.segment, DATE_TRUNC('month', da.dt_reference)
            ORDER BY da.dt_reference ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) - 1 AS n_business_days_since_pipe,
        da.n_contracts_at_reference, da.n_contracts_acc,
        da.n_invoices_DT2_at_reference, da.n_invoices_DT2_acc,
        da.recovered_invoices_DT2_acc,
        da.due_amount_DT2_at_reference, da.due_amount_DT2_acc,
        da.recovered_amount_DT2_acc,
        COALESCE(da.recovered_amount_DT2_acc / NULLIF(da.due_amount_DT2_acc, 0), 0)
            AS recovery_rate_amount_t2,
        dd.is_brz_fintech_business_day,
        dd.next_brz_fintech_business_day,
        DATE_TRUNC('month', da.dt_reference) AS dt_month_ref,
        da.dt_pipe, da.dt_reference
    FROM daily_accumulation AS da
    LEFT JOIN dw_public.dim_date AS dd ON dd.date = da.dt_reference
),
final_ordering AS (
    SELECT
        bdc.*,
        ROW_NUMBER() OVER (
            PARTITION BY bdc.n_business_days_since_pipe, bdc.dt_month_ref, bdc.segment
            ORDER BY bdc.dt_reference DESC
        ) AS rn_business_day
    FROM business_day_context AS bdc
)
SELECT
    segment,
    rn_business_day,
    n_business_days_since_pipe,
    days_to_pipe,
    n_contracts_at_reference, n_contracts_acc,
    n_invoices_DT2_at_reference, n_invoices_DT2_acc,
    recovered_invoices_DT2_acc,
    due_amount_DT2_at_reference, due_amount_DT2_acc,
    recovered_amount_DT2_acc, recovery_rate_amount_t2,
    is_brz_fintech_business_day, next_brz_fintech_business_day,
    dt_month_ref, dt_pipe, dt_reference,
    NOW() AS ts_load
FROM final_ordering
WHERE segment IS NOT NULL;
```

### 3. Same query, but using Chargehub audiences

For the **operational live view**, replace the `fact_contract_features_timeline` segmentation with the Chargehub audience allocation. Used to materialize `metric_fintech.daily_recovery_chargehub_audiences`.

```sql
WITH segment_allocation AS (
    SELECT DISTINCT
        dt_last_appearance,
        segment_name,
        audience_name,
        id_contract
    FROM datalake_debt_recovery.segmentation_distribution
    WHERE is_active = TRUE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id_contract, dt_last_appearance
        ORDER BY ts_entered_segment DESC, ts_entered_audience DESC
    ) = 1
)
-- Then use COALESCE(sda.audience_name, 'Unsegmented') wherever
-- Query 2 uses cft.segmentation, joining segment_allocation on
-- (sda.dt_last_appearance = iwt.dt_reference AND sda.id_contract = iwt.sk_contract)
-- and filter `sda.dt_last_appearance IS NOT NULL` in invoice_month_boundaries.
```

### 4. Recovery for an arbitrary date range (ad-hoc filter on any segment)

When you need a **custom slice** that the materialized tables don't cover (e.g. a specific Chargehub audience, a specific dl-segment, a non-monthly window), use this pattern. Key idea: explode the wallet over `dim_date`, then **back-fill** segment / amount features so an invoice that leaves the timeline (because it was paid) keeps contributing the right denominator until the end of the requested window.

```sql
WITH chargehub_allocation AS (
    SELECT DISTINCT
        dt_last_appearance,
        segment_name,
        audience_name,
        id_contract
    FROM datalake_debt_recovery.segmentation_distribution AS m
    LEFT JOIN dw_collections_segmentation.fact_contract_wallet_timeline AS f
        ON f.sk_contract = m.id_contract AND f.dt_reference = m.dt_last_appearance
    WHERE m.is_active
    -- Optional early filter on audience to reduce volume:
    -- AND m.audience_name IN ('ACTIVE_STOCK_PRE_EVICTIONS_AQA', 'ACTIVE_STOCK_PRE_EVICTIONS_WQA')
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id_contract, dt_last_appearance
        ORDER BY ts_entered_segment DESC, ts_entered_audience DESC
    ) = 1
),
minimal_invoice_select AS (
    SELECT
        m.dt_reference,
        m.dt_begin,
        m.dt_paid,
        COALESCE(ch.segment_name, 'Unsegmented in Chargehub') AS chargehub_segment,
        f.segmentation AS dl_segment,
        f.macro_segmentation,
        m.sk_invoice,
        m.sk_contract,
        t.dt_pipe AS dt_pipe,
        m.recovered_amount,
        ABS(m.due_amount) AS due_amount,
        m.invoice_delay_t2,
        m.payment_status
    FROM dw_collections_segmentation.fact_invoice_wallet_timeline AS m
    LEFT JOIN dw_collections_segmentation.fact_contract_wallet_timeline AS t
        ON t.dt_reference = m.dt_reference AND t.sk_contract = m.sk_contract
    LEFT JOIN dw_collections_segmentation.fact_contract_features_timeline AS f
        ON f.dt_reference = m.dt_reference AND f.sk_contract = m.sk_contract
    LEFT JOIN chargehub_allocation AS ch
        ON ch.dt_last_appearance = m.dt_reference AND ch.id_contract = m.sk_contract
    WHERE DATE_TRUNC('month', m.dt_reference) >= DATE('2025-10-01')   -- start of window
        AND m.dt_reference < DATE(CURRENT_DATE)
        -- Slice the universe here. Examples:
        -- AND f.segmentation = 'active-new-defaulter-high'
        AND COALESCE(ch.segment_name, 'Unsegmented in Chargehub') = 'ACTIVE_NEW_DEFAULTER_EARLY_HIGH'
),
answer_sheet AS (
    -- Cross-join the requested date window with every (sk_contract, sk_invoice)
    -- present in the slice, starting from each invoice's earliest appearance.
    SELECT
        d.date,
        m.sk_contract,
        m.sk_invoice
    FROM dw_public.dim_date AS d
    CROSS JOIN (
        SELECT sk_contract, sk_invoice, MIN(dt_reference) AS dt_begin
        FROM minimal_invoice_select
        GROUP BY 1, 2
    ) AS m
    WHERE DATE_TRUNC('month', d.date) >= DATE('2025-10-01')   -- same window
        AND d.date < DATE(CURRENT_DATE)
        AND d.date >= m.dt_begin
),
know_timeline AS (
    SELECT
        a.date, a.sk_contract, a.sk_invoice,
        d.chargehub_segment, d.dl_segment, d.macro_segmentation,
        d.recovered_amount, d.invoice_delay_t2, d.payment_status, d.due_amount
    FROM answer_sheet AS a
    LEFT JOIN minimal_invoice_select AS d
        ON a.sk_invoice = d.sk_invoice AND a.date = d.dt_reference
),
propagated_timeline AS (
    -- Back-fill (last non-null) so paid invoices keep their last known
    -- features after they disappear from the daily wallet.
    SELECT
        m.*,
        LAST_VALUE(chargehub_segment,    TRUE) OVER (PARTITION BY sk_invoice ORDER BY date) AS bb_fill_chargehub_segment,
        LAST_VALUE(dl_segment,           TRUE) OVER (PARTITION BY sk_invoice ORDER BY date) AS bb_fill_dl_segment,
        LAST_VALUE(macro_segmentation,   TRUE) OVER (PARTITION BY sk_invoice ORDER BY date) AS bb_fill_macro_segmentation,
        LAST_VALUE(recovered_amount,     TRUE) OVER (PARTITION BY sk_invoice ORDER BY date) AS bb_fill_recovered_amount,
        LAST_VALUE(invoice_delay_t2,     TRUE) OVER (PARTITION BY sk_invoice ORDER BY date) AS bb_fill_invoice_delay_t2,
        LAST_VALUE(payment_status,       TRUE) OVER (PARTITION BY sk_invoice ORDER BY date) AS bb_fill_payment_status,
        LAST_VALUE(due_amount,           TRUE) OVER (PARTITION BY sk_invoice ORDER BY date) AS bb_fill_due_amount
    FROM know_timeline AS m
),
database_cleaned_timeline AS (
    SELECT
        date, sk_contract, sk_invoice,
        COALESCE(due_amount,          bb_fill_due_amount)          AS _due_amount,
        COALESCE(recovered_amount,    bb_fill_recovered_amount)    AS _recovered_amount,
        COALESCE(invoice_delay_t2,    bb_fill_invoice_delay_t2)    AS _invoice_delay_t2,
        COALESCE(payment_status,      bb_fill_payment_status)      AS _payment_status,
        COALESCE(chargehub_segment,   bb_fill_chargehub_segment)   AS _chargehub_segment,
        COALESCE(dl_segment,          bb_fill_dl_segment)          AS _dl_segment,
        COALESCE(macro_segmentation,  bb_fill_macro_segmentation)  AS _macro_segmentation
    FROM propagated_timeline
)
SELECT
    date,
    _chargehub_segment,
    SUM(_due_amount)                                                                  AS due_amount_wallet,
    SUM(CASE WHEN _invoice_delay_t2 > 0 THEN _due_amount END)                         AS due_amount_wallet_dt2,
    SUM(_recovered_amount)                                                            AS recovered_amount,
    SUM(CASE WHEN _invoice_delay_t2 > 0 THEN _recovered_amount END)                   AS recovered_amount_dt2,
    COUNT(DISTINCT sk_invoice)                                                        AS n_invoices,
    COUNT(DISTINCT sk_contract)                                                       AS n_contracts,
    SUM(CASE WHEN _invoice_delay_t2 > 0 THEN _recovered_amount END)
        / NULLIF(SUM(CASE WHEN _invoice_delay_t2 > 0 THEN _due_amount END), 0)        AS rr_amount_t2
FROM database_cleaned_timeline
GROUP BY 1, 2
ORDER BY 1;
```

### 5. MTD parity for cross-month comparisons

To compare today's MTD recovery rate against MoB-1 / MoB-2 / a 4-month rolling average, you must align days **by their position within the month**, not by raw calendar day. The helper below picks the best-matching reference day per (segment, MoB) using one of three strategies.

| `flag_type` | Matching priority |
|-------------|-------------------|
| `BUSSINESS_DAYS_SINCE_PIPE` (default) | (1) Exact `n_business_days_since_pipe` if post-pipe, (2) closest absolute distance in `days_to_pipe`, (3) most recent date as tie-breaker. |
| `RUNNING_DAYS` | Closest `day(dt_reference)` to the reference day (e.g. matching "the 5th" across months). |
| `RUNNING_DAYS_SINCE_PIPE` | Closest `days_to_pipe` regardless of business-day flag. |

```python
def get_parity_table(day_, table_source, flag_type='BUSSINESS_DAYS_SINCE_PIPE'):
    """Build an MTD parity comparison for `day_` against MoB 0/1/2 and a 4-MoB average.

    Args:
        day_:         Reference day (e.g. '2025-04-25').
        table_source: One of the metric_fintech.daily_recovery_* tables.
        flag_type:    Matching strategy (see table above).
    """

    if flag_type == 'BUSSINESS_DAYS_SINCE_PIPE':
        sql_parity = f'''
        parallel_business_reference_point AS (
            SELECT
              12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                + MONTH(gr.m_ref) - MONTH(m.dt_month_ref) AS mob,
              m.*
            FROM {table_source} AS m
            INNER JOIN get_ref_dates AS gr
              ON m.segment = gr.segment
            WHERE 12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                  + MONTH(gr.m_ref) - MONTH(m.dt_month_ref) BETWEEN 0 AND 4
            QUALIFY ROW_NUMBER() OVER (
              PARTITION BY
                m.segment,
                12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                  + MONTH(gr.m_ref) - MONTH(m.dt_month_ref)
              ORDER BY
                CASE WHEN gr.days_to_pipe_ref >= 0
                      AND m.n_business_days_since_pipe = gr.n_ref THEN 0 ELSE 1 END ASC,
                ABS(m.days_to_pipe - gr.days_to_pipe_ref) ASC,
                m.dt_reference DESC
            ) = 1
        ),
        '''

    elif flag_type == 'RUNNING_DAYS':
        sql_parity = f'''
        parallel_business_reference_point AS (
            SELECT
              12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                + MONTH(gr.m_ref) - MONTH(m.dt_month_ref) AS mob,
              m.*
            FROM {table_source} AS m
            INNER JOIN get_ref_dates AS gr ON m.segment = gr.segment
            WHERE 12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                  + MONTH(gr.m_ref) - MONTH(m.dt_month_ref) BETWEEN 0 AND 4
            QUALIFY ROW_NUMBER() OVER (
              PARTITION BY
                m.segment,
                12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                  + MONTH(gr.m_ref) - MONTH(m.dt_month_ref)
              ORDER BY
                ABS(DAY(m.dt_reference) - DAY(gr.d_ref)) ASC,
                m.dt_reference DESC
            ) = 1
        ),
        '''

    elif flag_type == 'RUNNING_DAYS_SINCE_PIPE':
        sql_parity = f'''
        parallel_business_reference_point AS (
            SELECT
              12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                + MONTH(gr.m_ref) - MONTH(m.dt_month_ref) AS mob,
              m.*
            FROM {table_source} AS m
            INNER JOIN get_ref_dates AS gr ON m.segment = gr.segment
            WHERE 12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                  + MONTH(gr.m_ref) - MONTH(m.dt_month_ref) BETWEEN 0 AND 4
            QUALIFY ROW_NUMBER() OVER (
              PARTITION BY
                m.segment,
                12 * (YEAR(gr.m_ref) - YEAR(m.dt_month_ref))
                  + MONTH(gr.m_ref) - MONTH(m.dt_month_ref)
              ORDER BY
                ABS(m.days_to_pipe - gr.days_to_pipe_ref) ASC,
                m.dt_reference DESC
            ) = 1
        ),
        '''

    else:
        return "No logic found for parity"

    sql_business_day_parity = f'''
    WITH get_ref_dates AS (
        SELECT DISTINCT
            segment,
            dt_reference                  AS d_ref,
            rn_business_day               AS rn_ref,
            n_business_days_since_pipe    AS n_ref,
            dt_month_ref                  AS m_ref,
            days_to_pipe                  AS days_to_pipe_ref
        FROM {table_source}
        WHERE dt_reference = DATE('{day_}')
    ),

    {sql_parity}

    avg_4_mobs AS (
        SELECT
            segment,
            SUM(recovered_amount_DT2_acc) / NULLIF(SUM(due_amount_DT2_acc), 0)
                AS avg_recovery_rate_amount_t2,
            AVG(due_amount_DT2_acc)        AS avg_due_amount_DT2_acc,
            AVG(recovered_amount_DT2_acc)  AS avg_recovered_amount_DT2_acc,
            AVG(n_contracts_acc)           AS avg_n_contracts_acc,
            AVG(n_invoices_DT2_acc)        AS avg_n_invoices_DT2_acc
        FROM parallel_business_reference_point
        WHERE mob BETWEEN 1 AND 4
        GROUP BY 1
    )

    SELECT
        m0.dt_reference,
        m0.segment,
        m0.days_to_pipe,

        -- Current month (MoB 0)
        m0.n_contracts_acc,
        m0.n_invoices_DT2_acc,
        m0.due_amount_DT2_acc,
        m0.recovered_amount_DT2_acc,
        m0.recovery_rate_amount_t2,

        (m0.recovery_rate_amount_t2 - m1.recovery_rate_amount_t2)         AS VAR_M1_ABS_recovery_rate_amount_t2,
        (m0.recovery_rate_amount_t2 - m2.recovery_rate_amount_t2)         AS VAR_M2_ABS_recovery_rate_amount_t2,
        (m0.recovery_rate_amount_t2 - a.avg_recovery_rate_amount_t2)      AS VAR_AVG4_ABS_recovery_rate_amount_t2,

        -- MoB 1 comparisons
        m1.n_contracts_acc                                                AS MOB1_n_contracts_acc,
        (m0.n_contracts_acc - m1.n_contracts_acc)                         AS VAR_M1_ABS_n_contracts_acc,
        (m0.n_contracts_acc - m1.n_contracts_acc) / NULLIF(m1.n_contracts_acc, 0)
                                                                          AS VAR_M1_REL_n_contracts_acc,
        m1.n_invoices_DT2_acc                                             AS MOB1_n_invoices_DT2_acc,
        (m0.n_invoices_DT2_acc - m1.n_invoices_DT2_acc)                   AS VAR_M1_ABS_n_invoices_DT2_acc,
        (m0.n_invoices_DT2_acc - m1.n_invoices_DT2_acc) / NULLIF(m1.n_invoices_DT2_acc, 0)
                                                                          AS VAR_M1_REL_n_invoices_DT2_acc,
        m1.due_amount_DT2_acc                                             AS MOB1_due_amount_DT2_acc,
        (m0.due_amount_DT2_acc - m1.due_amount_DT2_acc)                   AS VAR_M1_ABS_due_amount_DT2_acc,
        (m0.due_amount_DT2_acc - m1.due_amount_DT2_acc) / NULLIF(m1.due_amount_DT2_acc, 0)
                                                                          AS VAR_M1_REL_due_amount_DT2_acc,
        m1.recovered_amount_DT2_acc                                       AS MOB1_recovered_amount_DT2_acc,
        (m0.recovered_amount_DT2_acc - m1.recovered_amount_DT2_acc)       AS VAR_M1_ABS_recovered_amount_DT2_acc,
        (m0.recovered_amount_DT2_acc - m1.recovered_amount_DT2_acc) / NULLIF(m1.recovered_amount_DT2_acc, 0)
                                                                          AS VAR_M1_REL_recovered_amount_DT2_acc,
        m1.recovery_rate_amount_t2                                        AS MOB1_recovery_rate_amount_t2,

        -- MoB 2 comparisons
        m2.n_contracts_acc                                                AS MOB2_n_contracts_acc,
        (m0.n_contracts_acc - m2.n_contracts_acc)                         AS VAR_M2_ABS_n_contracts_acc,
        (m0.n_contracts_acc - m2.n_contracts_acc) / NULLIF(m2.n_contracts_acc, 0)
                                                                          AS VAR_M2_REL_n_contracts_acc,
        m2.n_invoices_DT2_acc                                             AS MOB2_n_invoices_DT2_acc,
        (m0.n_invoices_DT2_acc - m2.n_invoices_DT2_acc)                   AS VAR_M2_ABS_n_invoices_DT2_acc,
        (m0.n_invoices_DT2_acc - m2.n_invoices_DT2_acc) / NULLIF(m2.n_invoices_DT2_acc, 0)
                                                                          AS VAR_M2_REL_n_invoices_DT2_acc,
        m2.due_amount_DT2_acc                                             AS MOB2_due_amount_DT2_acc,
        (m0.due_amount_DT2_acc - m2.due_amount_DT2_acc)                   AS VAR_M2_ABS_due_amount_DT2_acc,
        (m0.due_amount_DT2_acc - m2.due_amount_DT2_acc) / NULLIF(m2.due_amount_DT2_acc, 0)
                                                                          AS VAR_M2_REL_due_amount_DT2_acc,
        m2.recovered_amount_DT2_acc                                       AS MOB2_recovered_amount_DT2_acc,
        (m0.recovered_amount_DT2_acc - m2.recovered_amount_DT2_acc)       AS VAR_M2_ABS_recovered_amount_DT2_acc,
        (m0.recovered_amount_DT2_acc - m2.recovered_amount_DT2_acc) / NULLIF(m2.recovered_amount_DT2_acc, 0)
                                                                          AS VAR_M2_REL_recovered_amount_DT2_acc,
        m2.recovery_rate_amount_t2                                        AS MOB2_recovery_rate_amount_t2,

        -- 4-MoB rolling average comparisons
        a.avg_n_contracts_acc                                             AS AVG4_n_contracts_acc,
        (m0.n_contracts_acc - a.avg_n_contracts_acc)                      AS VAR_AVG4_ABS_n_contracts_acc,
        (m0.n_contracts_acc - a.avg_n_contracts_acc) / NULLIF(a.avg_n_contracts_acc, 0)
                                                                          AS VAR_AVG4_REL_n_contracts_acc,
        a.avg_n_invoices_DT2_acc                                          AS AVG4_n_invoices_DT2_acc,
        (m0.n_invoices_DT2_acc - a.avg_n_invoices_DT2_acc)                AS VAR_AVG4_ABS_n_invoices_DT2_acc,
        (m0.n_invoices_DT2_acc - a.avg_n_invoices_DT2_acc) / NULLIF(a.avg_n_invoices_DT2_acc, 0)
                                                                          AS VAR_AVG4_REL_n_invoices_DT2_acc,
        a.avg_due_amount_DT2_acc                                          AS AVG4_due_amount_DT2_acc,
        (m0.due_amount_DT2_acc - a.avg_due_amount_DT2_acc)                AS VAR_AVG4_ABS_due_amount_DT2_acc,
        (m0.due_amount_DT2_acc - a.avg_due_amount_DT2_acc) / NULLIF(a.avg_due_amount_DT2_acc, 0)
                                                                          AS VAR_AVG4_REL_due_amount_DT2_acc,
        a.avg_recovered_amount_DT2_acc                                    AS AVG4_recovered_amount_DT2_acc,
        (m0.recovered_amount_DT2_acc - a.avg_recovered_amount_DT2_acc)    AS VAR_AVG4_ABS_recovered_amount_DT2_acc,
        (m0.recovered_amount_DT2_acc - a.avg_recovered_amount_DT2_acc) / NULLIF(a.avg_recovered_amount_DT2_acc, 0)
                                                                          AS VAR_AVG4_REL_recovered_amount_DT2_acc,
        a.avg_recovery_rate_amount_t2                                     AS AVG4_recovery_rate_amount_t2,

        -- Debug
        m1.dt_reference AS DEBUG_m1_dt_reference,
        m2.dt_reference AS DEBUG_m2_dt_reference

    FROM parallel_business_reference_point AS m0
    LEFT JOIN parallel_business_reference_point AS m1
      ON m1.segment = m0.segment AND m1.mob = 1
    LEFT JOIN parallel_business_reference_point AS m2
      ON m2.segment = m0.segment AND m2.mob = 2
    LEFT JOIN avg_4_mobs AS a
      ON a.segment = m0.segment
    WHERE m0.mob = 0
      AND m0.segment <> 'active-current'
      AND m0.segment <> 'ended-current'
    '''

    return spark.sql(sql_business_day_parity).toPandas()
```

**Notes:**

- The same parity logic can be applied directly in SQL — wrap `get_ref_dates` and `parallel_business_reference_point` as CTEs and skip the Python wrapper.
- `BUSSINESS_DAYS_SINCE_PIPE` is the recommended default for operational dashboards. Use `RUNNING_DAYS` only when the business question is calendar-day driven (e.g. "compare day 5 of the month").
- The `WHERE m0.mob = 0` filter keeps a single row per `(segment, dt_reference)` representing the current MoB; remove it if you want all MoBs in the output.
