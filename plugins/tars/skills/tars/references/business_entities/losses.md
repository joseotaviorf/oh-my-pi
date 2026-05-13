# Losses

## Overview

Losses represent the accounting and financial phase of the credit lifecycle. It occurs when a company determines that a specific debt is unlikely to be collected and must be officially recognized as an expense. This process ensures the company's financial health is accurately reflected by removing "toxic" or uncollectible assets from the books.

- **Objective:** Provide an accurate picture of financial health by removing uncollectible assets.
- **Asset status:** Value is removed from the Balance Sheet (asset) and recorded as a loss in the P&L (profit and loss).
- **Common actions:** Write-offs (removing debt from books) and utilizing the allowance for doubtful accounts (provisions).

The **Fintech DW losses** model lives under schema **`dw_losses`** and is built mainly by DAG **`dw_losses`** (Databricks, layer `dw`, custom schema `losses`, `query_delta` workflow). It loads **`fact_closing`**, **`fact_delay`**, **`fact_provision`**, **`fact_losses`**, **`dim_provision_factor`**, and **`dim_bill_items`** via full load. The DAG runs on the **day after the first business day of the month**.

Related receivables modeling (same schema, separate DAG): **`dw_accounts_receivable`** loads **`dw_losses.fact_accounts_receivable`** for losses recovery — not defined under `dags/fintech/dw_losses`.

## Synonyms

| Term | Meaning |
|------|---------|
| **Bad debt** | Uncollectible accounts receivable |
| **Write-off / charge-off** | Removing the debt from the primary accounting ledger |
| **PDD / provision** | Allowance for doubtful accounts |
| **Net charge-off (NCO)** | Total write-offs minus subsequent recoveries |

## Tables

| You need… | Use this table |
|-----------|----------------|
| Filtered, analysis-ready loss rows (provision + closing, MoM **losses**) | `dw_losses.fact_losses` |
| Monthly provision (PDD) balances and factors per invoice | `dw_losses.fact_provision` |
| Monthly closing snapshot of invoices (amounts, payment state, guarantee, dates) | `dw_losses.fact_closing` |
| Delay contamination rules and day ranges (PD buckets) | `dw_losses.fact_delay` |
| Bill lines per invoice with cluster for provision attribution | `dw_losses.dim_bill_items` |
| Provision factor lookup (risk × rule × PD range × effective dates) | `dw_losses.dim_provision_factor` |
| Outstanding receivables / recovery-oriented facts | `dw_losses.fact_accounts_receivable` (from **`dw_accounts_receivable`** DAG) |

### Grain and joins

- **Primary keys for time-series facts:** `(sk_invoice, sk_contract, dt_closing)` — `dt_closing` is the **last day of the month** (closing date).
- **Typical joins:** `fact_provision` ↔ `fact_closing` ↔ `fact_delay` on `sk_invoice`, `sk_contract`, and `dt_closing`. **`dim_bill_items`** on `sk_invoice` and **`dt_closing`**.
- **Contract context:** join `sk_contract` to `dw_rent.dim_contract` (or other rent DW entities) when you need contract attributes.

### `fact_closing`

Fact table for **closing** information in the losses model (sources: `datalake_losses.closing` ∪ `datalake_losses.historical_closing`). Useful fields include:

| Field | Role |
|-------|------|
| `sk_invoice`, `sk_contract` | Invoice and contract IDs |
| `due_amount`, `invoice_paid_amount`, `invoice_type` | Amounts and billing frequency/type |
| `payment_status` | Payment state (open, paid, canceled, written down, etc.) |
| `closing_month_status` | Contract status in the closing month |
| `is_guarantee_paid`, `contract_guarantee` | Guarantee type / whether guarantee is paid |
| `is_international`, `is_before_started`, `is_writtendown_in_dead_time`, `has_repair_offboarding_bill_item` | Standard losses filters |
| `accrual_year_month` | Accrual period as `yyyymm` |
| `origin_factor` | Whether the row comes from current closing vs historical snapshot |
| Date columns | `dt_closing`, `dt_due`, `dt_paid`, `dt_sent`, `dt_contract_signature`, `dt_annulment`, `dt_snapshot` (and write-off / canceled dates in the pipeline where present) |

### `fact_provision`

Fact table for **provision (PDD)** per invoice at each closing. Includes the **chosen** `provision_balance` and `provision_factor`, plus grids of balances under delay rules **A–E** and provision rules **1–7** (`provision_balance_p{1..7}_delay_{a|b|c|d|e}`) from the datalake. Other important columns: `invoice_account_type`, `payment_status`, `invoice_status`, `due_amount`, **`deal_status`**, `risk_type`, `delay_contamined_range`, **`paid_amount`**, adjusted due/paid dates (`dt_due_adjs`, `dt_paid_adjs`, etc.), **`dt_write_off`**, **`dt_snapshot`**, `is_write_off`, `is_contract_write_off`, and the same international / before-started / repair-offboarding flags as closing.

### `fact_delay`

Fact table for **delay** and **contamination** rules used in provisioning:

| Rule | Idea (from metadata) |
|------|------------------------|
| **A** | Contaminate all deal invoices from the negotiation anchor; natural debt keeps rolling even if the deal is paid |
| **B** | If the deal is broken, worsen roll only when the invoice delay exceeds the delay at negotiation |
| **C** | If the deal is broken → contaminate like A; otherwise keep delay as at negotiation |
| **D** | If the deal is broken → contaminated delay = invoice delay + delay at negotiation |
| **E** | If **any** invoice is delayed **and** the contract has an active negotiation → contaminated delay = invoice delay + delay at negotiation |

The table exposes `deal_delay_rule_*`, `pd_range_rule_*`, `delay_invoice_range*`, and `delay_contamined_range*` variants (per rule) plus the **applied** `delay_invoice_range` and `delay_contamined_range`. Also includes `risk_type`, `due_amount`, `payment_status`, and the usual scope flags.

### `fact_losses`

Curated table that **applies business filters**, joins **`fact_provision`** to **`fact_closing`**, enriches **city** from `dw_rent.fact_house_listings` + `dw_public.dim_region`, and computes **month-over-month loss** as the change in **`provision_balance`** (current month vs previous month for the same invoice/contract). Typical filters in the build include: `due_amount < 0`, exclude `payment_status = 'canceled'`, `is_writtendown_in_dead_time = FALSE`, `is_international = FALSE`, `is_before_started = FALSE`, and **repair offboarding** logic (before Feb 2024 vs from Feb 2024 onward). Documented columns in metadata include `losses` (PDD delta), `provision_balance`, `due_amount`, `dt_cohort` / `dt_closing`, `risk_group` / `guarantee_group` / `provisional_group`, `delay_contaminated_range`, and lineage-driven attributes aligned with provision and closing.

### `dim_bill_items`

Invoice-level **bill lines** with suggested **clusters** for analytics (teams may define alternate groupings). Key columns: `sk_invoice`, `bill_item_name`, `bill_item_cluster_name`, `bill_item_due_amount`, `dt_closing`.

**Official cluster labels** (`bill_item_cluster_name`):

| Cluster | Meaning |
|---------|---------|
| **ACORDO** | Negotiation of prior debt (e.g. `DEBIT-NEGOTIATION`) |
| **CONDOMINIO** | Condominium-related charges internalized by 5A |
| **MULTA-RECISORIA** | Early termination fee (`EARLY-TERMINATION-FEE`) |
| **MULTAS ONGOING** | Late fees from prior delay (`PROPERTY-DAMAGE-FINE`, `FINE-AND-INTEREST`) |
| **RENTAL-CORE** | Core monthly invoice composition (`RENTAL`, `IPTU`, `SERVICE-FEE`, `HOME-INSURANCE`, `CONDOMINIUM`, etc.) |
| **REPAROS** | Repairs (`REPAIR-OFFBOARDING`, `REPAIR-ONGOING`, protection/acquittal fund lines, etc.) |
| **UTILIDADES** | Utilitiesdefaults (`LIGHT-WATER-OR-GAS`, `UTILITIES-DEFAULTING`) |
| **GUARANTEE-RENOVATION** | Guarantee charges after 12 months (`RENTAL-GUARANTEE-FEE`, `PRO-GUARANTOR-5A-INSTALLMENT`) |
| **OUTROS** | Everything else |

### `dim_provision_factor`

**Junk dimension** listing which **provision factor** applies by **`sk_factor_risk`**, **`sk_provision_rule`**, **`pd_range`**, **`risk_type`**, and **`provision_name`**, with **`begin_date_application`** / **`end_date_application`** for versioned rules.

## Key metrics

| Metric | Definition / source |
|--------|---------------------|
| **NPL (non-performing loans)** | Sum of loans/invoices materially past due (often 90+ days) — define using `delay_contamined_range` / business rules |
| **Net charge-off rate** | Written-off debt (minus recoveries) / average receivables |
| **Provision balance** | `fact_provision.provision_balance` — expected loss reserve for the invoice at closing |
| **Losses / losses hist** | Month-over-month change in provision (e.g. `fact_losses.losses` or attributed slice via `dim_bill_items`) |

## Relationships with other entities

- **Invoices (1:1):** Loss facts are keyed by **`sk_invoice`** (+ **`dt_closing`**).
- **Contract (N:1):** Many invoices per contract via **`sk_contract`**; join to **`dw_rent.dim_contract`** for contract attributes.
- **Bill items (1:N):** One provisioned invoice may map to many rows in **`dim_bill_items`**; allocate provision with **`bill_item_due_amount`** / **`due_amount`** (see golden query below).

## Dos and don'ts

**Do:**

- Filter **`is_international = false`** and **`is_before_started = false`** for standard domestic portfolio views.
- Use **`date_trunc('month', dt_closing)`** when comparing provision across periods.
- Distinguish **`payment_status`** (cash/collection flow) from **`invoice_status`** / accounting labels (e.g. **Baixado**).
- Apply **`has_repair_offboarding_bill_item`** consistently: for closings **on or after 2024-02-01**, align with the rule used in **`fact_losses`** (exclude repair-offboarding rows where the model sets the flag to true).

**Don't:**

- Treat **`due_amount`** and **`provision_balance`** as the same: provision is the **expected loss portion**, not full notional.
- Include **written down** or **canceled** invoices in bases that should reflect active provision unless the question explicitly requires them.
- Ignore repair-offboarding filters after Feb 2024 when comparing to official losses reports.

## Golden queries

### Monthly losses by bill item cluster (`losses_hist`)

Allocates provision to bill-item clusters and computes month-over-month change (`losses_hist`).

```sql
SELECT
    date_trunc('month', CAST(dt_closing AS TIMESTAMP)) AS dt_closing,
    bill_item_cluster_name,
    sum(losses_hist) AS total_losses_hist
FROM (
    WITH baseline AS (
        SELECT
            m.dt_closing,
            m.sk_invoice,
            COALESCE(f.bill_item_cluster_name, 'UNCLASSIFIED') AS bill_item_cluster_name,
            CASE
                WHEN due_amount <> 0 THEN (provision_balance / due_amount) * bill_item_due_amount
                ELSE provision_balance
            END AS bill_item_provision
        FROM dw_losses.fact_provision AS m
        LEFT JOIN dw_losses.dim_bill_items AS f
            ON (f.sk_invoice = m.sk_invoice AND f.dt_closing = m.dt_closing)
        WHERE m.payment_status <> 'written down'
          AND m.is_international = false
          AND m.is_before_started = false
          AND NOT (m.dt_closing >= DATE('2024-02-01') AND has_repair_offboarding_bill_item)
    ),
    all_provision_outputs AS (
        SELECT dt_closing, bill_item_cluster_name, SUM(COALESCE(bill_item_provision, 0)) AS p_hist
        FROM baseline
        GROUP BY 1, 2
    ),
    losses_table AS (
        SELECT
            m.dt_closing,
            m.bill_item_cluster_name,
            m.p_hist,
            f.p_hist AS p_hist_prev
        FROM all_provision_outputs AS m
        LEFT JOIN all_provision_outputs AS f
            ON (f.dt_closing = DATE_ADD('month', -1, m.dt_closing)
            AND f.bill_item_cluster_name = m.bill_item_cluster_name)
    )
    SELECT *, p_hist - p_hist_prev AS losses_hist
    FROM losses_table
    WHERE p_hist_prev IS NOT NULL
) AS virtual_table
WHERE dt_closing >= DATE '2025-04-01'
GROUP BY 1, 2
ORDER BY total_losses_hist DESC;
```

### Total provisioned balance vs invoice amount

Compares receivable exposure to provisioned amount at closing (managerial view).

```sql
WITH base_gerencial AS (
  SELECT DISTINCT
    date(date_trunc('month', fc.dt_closing)) AS month_closing,
    fc.due_amount * (-1) AS invoice_amount,
    fp.provision_balance * (-1) AS provisioned_balance
  FROM dw_losses.fact_closing AS fc
  LEFT JOIN dw_losses.fact_delay AS fd
    ON fc.sk_invoice = fd.sk_invoice AND fc.dt_closing = fd.dt_closing
  LEFT JOIN dw_losses.fact_provision AS fp
    ON fc.sk_invoice = fp.sk_invoice AND fc.dt_closing = fp.dt_closing
  WHERE fc.due_amount < 0
    AND fc.payment_status <> 'canceled'
    AND fp.invoice_status <> 'Baixado'
    AND fc.is_international = false
    AND (fc.dt_write_off > fc.dt_closing OR fc.dt_write_off IS NULL)
)
SELECT
    month_closing,
    SUM(invoice_amount) AS total_invoice_amount,
    SUM(provisioned_balance) AS total_provisioned_balance
FROM base_gerencial
GROUP BY 1
ORDER BY 1 DESC;
```

**Note:** Golden queries assume columns such as **`dt_write_off`** exist on **`fact_closing`** in your environment (populated from the closing pipeline). If a column is missing, check the latest **`fact_closing`** definition in the repo.
