# Accounting Funnel (Canudo Contábil / Accounting Straw)

## Overview

The **Accounting Funnel** (a.k.a. **Accounting Straw** / **Canudo Contábil**) is QuintoAndar's **financial-reconciliation backbone** — the strategic control used to identify discrepancies between the **product systems** (the origin of a financial event) and **SAP** (the accounting system of record). It is the company's official candidate for the **financial reconciliation tool**.

It traces every accounting event end-to-end across the pipeline:

**Source product → SAP_Gateway → SAP**

For each event it answers a single question: *did what happened in the product correctly, completely, on time, and faithfully land in SAP?* The model is aligned with the **ISA 315** auditing standard for identifying risks of material misstatement.

> **Scope note:** The Accounting Funnel reconciles **product systems against SAP** — it does **not** involve banking data. To reconcile banking data, please consult `bank_reconciliation.md`.

### Tie-out methodology ("batida")

An account is only considered **reconciled / "batida" (ties out)** when there is conformity in **both directions**:

| View | Direction | What it validates |
|------|-----------|-------------------|
| **Straw** (`type = 'straw'`) | Origin (Product) → Destination (SAP) | Every event created in the product reached SAP correctly |
| **Reverse Straw** (`type = 'reverse straw'`) | Destination (SAP) → Origin (Product) | Every entry in SAP has a backing event in the product — detects accounting "noise" / entries that should **not** exist in a given account |

Accounts that reach **continuous conformity in both views** are classified as **self-reconciling**. Partial reconciliation is expressed as **Straw Compliance %** and **Reverse Straw Compliance %** (amount-weighted — see [Compliance Metrics](#compliance-metrics-amount-weighted)).

### The four "Golden Rules" (audit assertions)

The funnel validates four assertions, each materialized as a boolean column. `is_compliance` is the AND of the first three:

| Assertion | Column | Meaning |
|-----------|--------|---------|
| **Completeness** (Completude) | `is_completeness` | The same ID flows through all products until it arrives in SAP — nothing is dropped |
| **Correctness / Exactness** (Exatidão) | `is_correctness` | The entry arrived at SAP Gateway and SAP with the **correct amount** in the **right account** |
| **Temporality** (Temporalidade) | `is_temporality` | The entry was created in SAP at the **right time** (right accrual period) |
| **Compliance / Integrity** (Integridade) | `is_compliance` | All three above are TRUE simultaneously |

### Sources and expansion roadmap

| Source | Status | Scope |
|--------|--------|-------|
| **Retsuko** | Live | Rental (aluguel) accounting flows — provision, revenue share, revenue accounting, invoices, write-off, transactional, third parties |
| **SAP_Gateway** | Live | Intermediate accounting integration layer between product and SAP |
| **SAP** | Live | Accounting system of record (destination) |
| **Monopoly** | Live (Sep–Oct 2025) | ForSale payment flows — invoices, revenue share, provision |

All enrich models are unified into the DW table **`dw_sap_accounting_process.fact_sap_accounting_process`** via a large `UNION ALL` of straw and reverse-straw source models.

## Synonyms

| Term | Meaning |
|------|---------|
| **Canudo Contábil** | Accounting Funnel / Accounting Straw |
| **Straw / Canudo** | Origin → SAP validation (`type = 'straw'`) |
| **Reverse Straw / Canudo Reverso** | SAP → origin traceability (`type = 'reverse straw'`) |
| **Batida / ties out / batido** | An account reconciled in both Straw and Reverse Straw views |
| **Self-reconciling** | Account in continuous conformity in both views |
| **Completude** | Completeness (`is_completeness`) |
| **Exatidão / Correctness** | Exactness (`is_correctness`) |
| **Temporalidade** | Temporality (`is_temporality`) |
| **Integridade / Compliance** | Integrity — all assertions TRUE (`is_compliance`) |
| **Retsuko** | Rental billing system (source) |
| **SAP_Gateway** | Accounting integration layer between product and SAP |
| **SAP** | Accounting system of record (destination) |
| **Monopoly** | ForSale payments system (source, since Sep–Oct 2025) |
| **ISA 315** | Auditing standard for identifying risks of material misstatement that the methodology aligns to |
| **Ruído contábil** | Accounting "noise" — entries in SAP without a backing product event (caught by Reverse Straw) |
| **Straw Compliance** | Amount-weighted % of compliant straw volume (origin → SAP) |
| **Reverse Straw Compliance** | Compliant straw volume / (non-compliant reverse-straw noise + compliant straw volume) — only for selected accounts |
| **Compliance % / conciliada** | Always refers to the amount-weighted formulas above — not event counts |

## Tables

| You need… | Use this table |
|-----------|----------------|
| Unified accounting funnel fact (all sources, straw + reverse straw) | `dw_sap_accounting_process.fact_sap_accounting_process` |
| Retsuko provision (straw) | `datalake_sap_accounting_process.retsuko_provision` |
| Retsuko provision (reverse) | `datalake_sap_accounting_process.retsuko_provision_reverse` |
| Retsuko revenue share (straw) | `datalake_sap_accounting_process.retsuko_revenue_share` |
| Retsuko revenue accounting (straw) | `datalake_sap_accounting_process.retsuko_revenue_accounting` |
| Retsuko invoice / invoice unified (straw) | `datalake_sap_accounting_process.retsuko_invoice` / `retsuko_invoice_unified` |
| Retsuko invoice unified (reverse) | `datalake_sap_accounting_process.retsuko_invoice_unified_reverse` |
| Retsuko write-off (straw) | `datalake_sap_accounting_process.retsuko_write_off` |
| Retsuko transactional (straw / reverse) | `datalake_sap_accounting_process.retsuko_transactional` / `retsuko_transactional_reverse` |
| Retsuko third parties (straw / reverse) | `datalake_sap_accounting_process.retsuko_third_parties` / `retsuko_third_parties_reverse` |
| Retsuko transactional third parties (straw / reverse) | `datalake_sap_accounting_process.retsuko_transactional_third_parties` / `retsuko_transactional_third_parties_reverse` |
| Reverse account groups (700005/700008/…, 420003/…, 420001/420002/420004, 513020) | `datalake_sap_accounting_process.reverse_accounts_*` |
| Reservation issuance kill-queue (straw) | `datalake_sap_accounting_process.kill_queue_reservation_issuance` |
| Kill-queue reverse | `datalake_sap_accounting_process.kill_queue_reverse` |
| For Rent bank settlement (straw) | `datalake_sap_accounting_process.for_rent_bank_settlement` |
| Monopoly invoices (straw / reverse) | `datalake_sap_accounting_process.monopoly_invoices` / `monopoly_invoices_reverse` |
| Monopoly revenue share (straw / reverse) | `datalake_sap_accounting_process.monopoly_revenue_share` / `monopoly_revenue_share_reverse` |
| Monopoly provision (straw / reverse) | `datalake_sap_accounting_process.monopoly_provision` / `monopoly_provision_reverse` |

**Pipeline:** DAG **`dw_sap_accounting_process`** (domain **Fintech**, owner `ae-finance-fintech@quintoandar.com.br`), workflow type **`query_delta`**, layer **`dw`**, custom schema **`sap_accounting_process`**. The DW fact is produced by `UNION ALL`-ing all enrich `datalake_sap_accounting_process.*` straw and reverse-straw models, each stamping a constant `type` (`'straw'` or `'reverse straw'`) and `ts_load = NOW()`.

### Key columns in `fact_sap_accounting_process`

Grain: **one row per accounting event × view** (a single event can appear once as `straw` and once as `reverse straw`).

| Column | Description |
|--------|-------------|
| `sk_accounting_process` | Surrogate key (`id_accounting_process`; for bank settlement it is `CONCAT('BANK-QA-FR-', id_finance_entity)`) |
| `id_business_entity` | Business entity ID from the source (e.g., contract) |
| `id_finance_entity` | Finance entity ID from the source (e.g., invoice) |
| `id_finance_entity_entry` | Finance entity entry ID from the source |
| `version` | Accounting version (`'kill-queue'` for the kill-queue model) |
| `business_unit` | Business unit (e.g., `for rent`) |
| `source_name` | Product that emitted the accounting information (`billing_source` for bank settlement) |
| `accounting_type` | Type of accounting it refers to (`bank` for bank settlement) |
| `account_number` | SAP account number |
| `accounting_name` | Account / accounting description |
| `source_amount` | Amount that **should** be created based on the source entry |
| `sap_amount` | Amount actually accounted in SAP |
| `accounting_balance` | Net SAP ledger balance for the entry and account (`SUM(debit_credit)` in the ledger, by `id_finance_entity_entry` × `account_number`). Available on Retsuko transactional and third-parties enrich models (straw and reverse straw). |
| `is_completeness` | Completeness assertion (same ID throughout the funnel until SAP) |
| `is_correctness` | Correctness assertion (right amount, right account at Gateway + SAP) |
| `is_temporality` | Temporality assertion (created in SAP at the right time) |
| `is_compliance` | TRUE only if completeness + correctness + temporality are all TRUE |
| `type` | View: `'straw'` (origin → SAP) or `'reverse straw'` (SAP → origin) |
| `accounting_process_status` | Status of the accounting process (NULL for kill-queue / bank settlement) |
| `error_description` | Description of any error in the process |
| `accrual_year_month` | Accrual period of the accounting entry (integer `YYYYMM`, e.g. `202605` for May 2026) |
| `dt_source_trigger` | Date that **starts** the funnel in the source (`dt_billing` for bank settlement) |
| `dt_sap_reference` | Date referenced in SAP |
| `dt_sap_created` | Date the entry was created in SAP |
| `dt_filter` | `COALESCE(dt_sap_reference, dt_source_trigger)` — canonical filter date |
| `ts_load` | Load timestamp (`NOW()` at build time) |

## Key Metrics

> **Compliance vs diagnostic metrics:** When a user asks about **compliance**, **Straw Compliance**, **Reverse Straw Compliance**, or whether an account is **conciliada / batida**, always use the **amount-weighted formulas** in the section below — **never** event counts or a simple `COUNT(is_compliance) / COUNT(*)`. Compliance is measured by **monetary volume**, grouped by `dt_filter` (cast to month) and `account_number`. Use `accrual_year_month` instead of `dt_filter` only when the user explicitly asks for the accounting accrual/competência view — the two fields represent different concepts (processing date vs. accounting period) and can yield materially different percentages for the same account/month.

### Compliance Metrics (amount-weighted)

The official **Straw Compliance** and **Reverse Straw Compliance** metrics are **amount-weighted percentages** per `account_number` × month, where month is derived from `dt_filter` (`DATE_TRUNC('month', CAST(dt_filter AS DATE))`) by default. Use `accrual_year_month` as the grouping key only for accounting-competência-specific questions.

| Metric | What it measures |
|--------|------------------|
| **Straw Compliance** | Share of **straw** monetary volume that is compliant (origin → SAP) |
| **Reverse Straw Compliance** | Share of **compliant straw volume** out of the total of compliant straw + non-compliant reverse-straw noise (SAP → origin) — **only defined for a fixed list of accounts** (see below) |

#### Straw Compliance (all accounts)

```sql
100.0 * SUM(IF(is_compliance = TRUE AND type = 'straw', COALESCE(ABS(source_amount), ABS(sap_amount)), 0))
  / NULLIF(SUM(IF(type = 'straw', COALESCE(ABS(source_amount), ABS(sap_amount)), 0)), 0)
```

- Uses **only** `type = 'straw'` rows.
- Amount priority: `COALESCE(ABS(source_amount), ABS(sap_amount))`.
- 100% = all product-originated volume for the period reached SAP correctly; below 100% = partial straw reconciliation.

#### Reverse Straw Compliance (selected accounts only)

Defined **only** when `account_number` is in:

`'113404'`, `'113406'`, `'113411'`, `'113412'`, `'113480'`, `'211406'`, `'211413'`, `'211415'`, `'420001'`, `'420002'`, `'420003'`, `'420004'`, `'420005'`, `'420006'`, `'420007'`, `'420008'`, `'420019'`, `'513020'`, `'420020'`, `'420025'`, `'611012'`, `'700004'`, `'700005'`, `'700006'`, `'700007'`, `'700008'`, `'700009'`, `'700010'`, `'700011'`, `'700013'`, `'420021'`, `'420022'`, `'420023'`, `'420032'`

For all other accounts, Reverse Straw Compliance is **NULL** (not applicable).

```sql
100.0 * SUM(IF(is_compliance = TRUE AND type = 'straw', COALESCE(ABS(sap_amount), ABS(source_amount)), 0))
  / NULLIF(
      SUM(IF(is_compliance = FALSE AND type = 'reverse straw', COALESCE(ABS(sap_amount), ABS(source_amount)), 0))
      + SUM(IF(is_compliance = TRUE AND type = 'straw', COALESCE(ABS(sap_amount), ABS(source_amount)), 0)),
      0
    )
```

- **Numerator:** compliant **straw** volume — amount priority `COALESCE(ABS(sap_amount), ABS(source_amount))`.
- **Denominator:** non-compliant **reverse straw** volume (accounting noise in SAP) **plus** compliant **straw** volume.
- This formula **intentionally mixes both views** in the denominator; do **not** compute it as `compliant reverse straw / total reverse straw`.
- Lower % = more SAP noise relative to compliant product volume. Example: account `113406` in `202605` yields **97.079%** Straw Compliance and **79.903%** Reverse Straw Compliance.

#### Interpreting compliance together

| Straw Compliance | Reverse Straw Compliance | Typical reading |
|------------------|--------------------------|-----------------|
| ~100% | ~100% | Fully reconciled in both directions |
| < 100% | any | Product events not landing correctly in SAP |
| ~100% | < 100% | Product → SAP is fine, but SAP has accounting noise without product backing |
| < 100% | < 100% | Breaks in both directions |

### Diagnostic metrics (root-cause analysis)

- **Event tie-out rate** — share of **events** (row count) with `is_compliance = TRUE`; useful for drill-down, **not** for answering compliance % questions.
- **Completeness / correctness / temporality rates** — share of `TRUE` per assertion, by source, account, or accrual period.
- **System divergence (`diff_systems`)** — `ABS(source_amount) - COALESCE(ABS(sap_amount), 0)`; amount mismatch between origin and SAP (≠ 0 signals a break).
- **Timing divergence (`diff_days`)** — `ABS(date_diff('day', dt_sap_reference, dt_source_trigger))`; lag between source trigger and SAP reference.
- **Reverse-straw noise volume** — `SUM(COALESCE(ABS(sap_amount), ABS(source_amount)))` on `type = 'reverse straw' AND NOT is_compliance`; the non-compliant reverse-straw component in the Reverse Straw Compliance denominator.
- **Reconciled amount** — `SUM(source_amount)` / `SUM(sap_amount)` filtered by compliance status, by `accrual_year_month`.

## Relationships with Other Entities

### Business entity / Contract (N:1)

`id_business_entity` links accounting events to the originating contract (`dw_rent.dim_contract` / Retsuko contract IDs).

### Finance entity / Invoice (N:1)

`id_finance_entity` links to Retsuko / product invoice IDs. The same `id_finance_entity` may appear across multiple accounting models (provision, revenue, invoice, write-off) and across both straw views.

### Payments (shared finance entity)

`id_finance_entity` aligns with the payments domain (`dw_payments_platform.fact_payment.id_finance_entity`) — useful to tie a SAP accounting entry back to the underlying payment / charge.

### Losses & Collections (shared identifiers)

Provision and write-off accounting events relate to the losses / AR domain (`dw_losses.fact_accounts_receivable`) and collections recovery models via invoice / contract IDs.

## Dos and Don'ts

**Do:**

- Use `dw_sap_accounting_process.fact_sap_accounting_process` as the single entry point — it already unifies every source and both views.
- When answering **compliance %** questions, use the **amount-weighted formulas** (Straw Compliance / Reverse Straw Compliance) grouped by `dt_filter` (cast to month) and `account_number` by default. Only switch to `accrual_year_month` when the question is explicitly about accounting competência.
- Always be explicit about the **view**: filter `type = 'straw'` for origin→SAP analysis and `type = 'reverse straw'` for SAP→origin traceability. An account "ties out" only when conformity holds in **both**.
- Use `dt_filter` (`COALESCE(dt_sap_reference, dt_source_trigger)`) as the canonical date for period filters; `CAST` it to `DATE` when grouping by day.
- Use `ABS()` on amounts when computing compliance or `diff_systems` — straw vs reverse-straw and debit/credit signs can flip, so compare magnitudes.
- Wrap `date_diff` in `ABS()` for `diff_days` — source and SAP dates are not guaranteed to be ordered.
- `COALESCE(ABS(sap_amount), 0)` when computing divergences — `sap_amount` is NULL when nothing was accounted in SAP (a completeness break).
- Treat `is_compliance` as the master flag, but drill into `is_completeness` / `is_correctness` / `is_temporality` to explain **why** an account did not tie out.
- Respect the **COALESCE order** in compliance formulas: Straw Compliance uses `COALESCE(ABS(source_amount), ABS(sap_amount))`; Reverse Straw Compliance uses `COALESCE(ABS(sap_amount), ABS(source_amount))`.

**Don't:**

- Don't answer compliance % questions with **event counts** (`COUNT(*)`, `SUM(IF(is_compliance, 1, 0))`) — compliance is **amount-weighted**.
- Don't compute Reverse Straw Compliance as `compliant reverse straw / total reverse straw` — the official formula mixes compliant **straw** (numerator) with non-compliant **reverse straw** + compliant **straw** (denominator).
- Don't report Reverse Straw Compliance for accounts outside the fixed list — it is **NULL** / not applicable.
- Don't mix `straw` and `reverse straw` rows in a single amount aggregation **unless** you are explicitly implementing the Reverse Straw Compliance formula.
- Don't assume `sap_amount` is populated — NULL means the entry never reached SAP (this is itself a finding).
- Don't filter on raw `dt_source_trigger` alone for SAP-period analysis — reverse and SAP-driven flows are better filtered by `dt_filter` / `dt_sap_reference`.
- Don't forget that certain technical/contra accounts (e.g. `'11036X'`, `'11004X'`) are typically excluded from reconciliation analyses — confirm the exclusion list with the finance owners.
- Don't read `version = 'kill-queue'` rows as normal accounting versions — they come from the kill-queue models and carry NULL `accounting_process_status` / `error_description`.
- Don't treat `accrual_year_month` and `dt_filter`-derived month as interchangeable — they measure different things (accounting period vs. processing/settlement date) and compliance % for the same account/month can diverge by dozens of points between the two.

## Golden Queries

### Query 1 — Reconciliation base with divergences (excluding technical accounts)

Builds the analytical base for tie-out analysis: per accounting event, the source vs SAP amounts, the four assertion flags, the view (`type`), and computed timing/amount divergences. Technical contra accounts are excluded.

```sql
SELECT
  sk_accounting_process,
  id_business_entity,
  id_finance_entity,
  id_finance_entity_entry,
  business_unit,
  accounting_type,
  account_number,
  accounting_name,
  source_amount,
  sap_amount,
  is_completeness,
  is_correctness,
  is_temporality,
  is_compliance,
  type,
  accounting_process_status,
  error_description,
  accrual_year_month,
  CAST(dt_source_trigger AS DATE) AS dt_source_trigger,
  dt_sap_reference,
  dt_sap_created,
  CAST(dt_filter AS DATE) AS dt_filter,
  ABS(date_diff('day', CAST(dt_sap_reference AS DATE), CAST(dt_source_trigger AS DATE))) AS diff_days,
  ABS(source_amount) - COALESCE(ABS(sap_amount), 0) AS diff_systems
FROM
  dw_sap_accounting_process.fact_sap_accounting_process
WHERE account_number NOT IN ('11036X', '11004X')
```

**Notes:**

- `diff_systems <> 0` flags a **correctness/completeness** break; `diff_days` quantifies the **temporality** gap.
- `type` distinguishes the Straw vs Reverse Straw view — keep it in the SELECT so downstream analysis can require conformity in both.
- The `account_number NOT IN ('11036X', '11004X')` filter drops technical contra accounts from the reconciliation universe.

### Query 2 — Event tie-out ("batida") by accrual period (diagnostic)

Counts **events** (not amounts). Use for root-cause drill-down; for compliance % use **Query 3** instead.

```sql
SELECT
  accrual_year_month,
  account_number,
  accounting_name,
  COUNT(*) AS total_events,
  SUM(IF(is_compliance, 1, 0)) AS compliant_events,
  SUM(IF(type = 'straw' AND NOT is_compliance, 1, 0)) AS straw_breaks,
  SUM(IF(type = 'reverse straw' AND NOT is_compliance, 1, 0)) AS reverse_straw_breaks,
  IF(
    SUM(IF(NOT is_compliance, 1, 0)) = 0,
    'ties out',
    'not reconciled'
  ) AS tie_out_status
FROM
  dw_sap_accounting_process.fact_sap_accounting_process
WHERE account_number NOT IN ('11036X', '11004X')
GROUP BY 1, 2, 3
ORDER BY accrual_year_month DESC, reverse_straw_breaks DESC, straw_breaks DESC
```

**Notes:**

- `straw_breaks` point to events that originated in the product but did not land correctly in SAP; `reverse_straw_breaks` point to SAP "noise" without a product backing.
- An account that consistently shows `tie_out_status = 'ties out'` across periods is a **self-reconciling** account.
- This query does **not** reproduce Straw / Reverse Straw Compliance percentages — see Query 3.

### Query 3 — Straw & Reverse Straw Compliance by account and period

Computes the official **amount-weighted** Straw and Reverse Straw Compliance percentages. Filter `account_number` and `dt_filter` date range as needed.

```sql
SELECT
  DATE_TRUNC('month', CAST(dt_filter AS DATE)) AS month_ref,
  account_number,
  accounting_name,
  100.0 * SUM(IF(is_compliance = TRUE AND type = 'straw', COALESCE(ABS(source_amount), ABS(sap_amount)), 0))
    / NULLIF(SUM(IF(type = 'straw', COALESCE(ABS(source_amount), ABS(sap_amount)), 0)), 0)
    AS straw_compliance_pct,
  IF(
    account_number IN (
      '113404', '113406', '113411', '113412', '113480', '211406', '211413', '211415',
      '420001', '420002', '420003', '420004', '420005', '420006', '420007', '420008',
      '420019', '513020', '420020', '420025', '611012', '700004', '700005', '700006',
      '700007', '700008', '700009', '700010', '700011', '700013', '420021', '420022',
      '420023', '420032'
    ),
    100.0 * SUM(IF(is_compliance = TRUE AND type = 'straw', COALESCE(ABS(sap_amount), ABS(source_amount)), 0))
      / NULLIF(
          SUM(IF(is_compliance = FALSE AND type = 'reverse straw', COALESCE(ABS(sap_amount), ABS(source_amount)), 0))
          + SUM(IF(is_compliance = TRUE AND type = 'straw', COALESCE(ABS(sap_amount), ABS(source_amount)), 0)),
          0
        ),
    NULL
  ) AS reverse_straw_compliance_pct
FROM
  dw_sap_accounting_process.fact_sap_accounting_process
WHERE account_number NOT IN ('11036X', '11004X')
  AND CAST(dt_filter AS DATE) BETWEEN :start_date AND :end_date
GROUP BY 1, 2, 3
ORDER BY month_ref DESC, account_number
```

**Example filter** for a single account and month:

```sql
-- account 113406, May 2026 → expect ~97.079% straw, ~79.903% reverse straw
WHERE account_number = '113406'
  AND CAST(dt_filter AS DATE) BETWEEN DATE '2026-05-01' AND DATE '2026-05-31'
```

**Notes:**

- `straw_compliance_pct` uses `COALESCE(ABS(source_amount), ABS(sap_amount))` — source amount first.
- `reverse_straw_compliance_pct` uses `COALESCE(ABS(sap_amount), ABS(source_amount))` — SAP amount first.
- Reverse Straw Compliance is **NULL** for accounts outside the `IN (...)` list.
- Group by `DATE_TRUNC('month', CAST(dt_filter AS DATE))` for monthly compliance reporting. Use `accrual_year_month` only when the question is explicitly about accounting competência.