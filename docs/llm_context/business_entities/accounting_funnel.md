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

Accounts that reach **continuous conformity in both views** are classified as **self-reconciling**.

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
| `is_completeness` | Completeness assertion (same ID throughout the funnel until SAP) |
| `is_correctness` | Correctness assertion (right amount, right account at Gateway + SAP) |
| `is_temporality` | Temporality assertion (created in SAP at the right time) |
| `is_compliance` | TRUE only if completeness + correctness + temporality are all TRUE |
| `type` | View: `'straw'` (origin → SAP) or `'reverse straw'` (SAP → origin) |
| `accounting_process_status` | Status of the accounting process (NULL for kill-queue / bank settlement) |
| `error_description` | Description of any error in the process |
| `accrual_year_month` | Accrual period of the accounting entry |
| `dt_source_trigger` | Date that **starts** the funnel in the source (`dt_billing` for bank settlement) |
| `dt_sap_reference` | Date referenced in SAP |
| `dt_sap_created` | Date the entry was created in SAP |
| `dt_filter` | `COALESCE(dt_sap_reference, dt_source_trigger)` — canonical filter date |
| `ts_load` | Load timestamp (`NOW()` at build time) |

## Key Metrics

- **Tie-out / reconciliation rate** — share of events with `is_compliance = TRUE` (ideally measured per `account_number` across **both** `straw` and `reverse straw`).
- **Completeness / correctness / temporality rates** — share of `TRUE` per assertion, by source, account, or accrual period.
- **System divergence (`diff_systems`)** — `ABS(source_amount) - COALESCE(ABS(sap_amount), 0)`; amount mismatch between origin and SAP (≠ 0 signals a break).
- **Timing divergence (`diff_days`)** — `ABS(date_diff('day', dt_sap_reference, dt_source_trigger))`; lag between source trigger and SAP reference.
- **Reverse-straw noise** — `reverse straw` rows failing `is_compliance` flag accounting entries in SAP without a backing product event.
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
- Always be explicit about the **view**: filter `type = 'straw'` for origin→SAP analysis and `type = 'reverse straw'` for SAP→origin traceability. An account "ties out" only when conformity holds in **both**.
- Use `dt_filter` (`COALESCE(dt_sap_reference, dt_source_trigger)`) as the canonical date for period filters; `CAST` it to `DATE` when grouping by day.
- Use `ABS()` on amounts when computing `diff_systems` — straw vs reverse-straw and debit/credit signs can flip, so compare magnitudes.
- Wrap `date_diff` in `ABS()` for `diff_days` — source and SAP dates are not guaranteed to be ordered.
- `COALESCE(ABS(sap_amount), 0)` when computing divergences — `sap_amount` is NULL when nothing was accounted in SAP (a completeness break).
- Treat `is_compliance` as the master flag, but drill into `is_completeness` / `is_correctness` / `is_temporality` to explain **why** an account did not tie out.

**Don't:**

- Don't mix `straw` and `reverse straw` rows in a single amount aggregation without intent — the same event can appear in both views and will be double-counted.
- Don't assume `sap_amount` is populated — NULL means the entry never reached SAP (this is itself a finding).
- Don't filter on raw `dt_source_trigger` alone for SAP-period analysis — reverse and SAP-driven flows are better filtered by `dt_filter` / `dt_sap_reference`.
- Don't forget that certain technical/contra accounts (e.g. `'11036X'`, `'11004X'`) are typically excluded from reconciliation analyses — confirm the exclusion list with the finance owners.
- Don't read `version = 'kill-queue'` rows as normal accounting versions — they come from the kill-queue models and carry NULL `accounting_process_status` / `error_description`.

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

### Query 2 — Account tie-out ("batida") by accrual period

An account ties out for a period only when **every** event is compliant in **both** views.

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
