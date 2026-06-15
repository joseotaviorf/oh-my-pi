# Bank Reconciliation

## Overview

Bank reconciliation (conciliação bancária) is the **FinOps control process** that verifies a payment or payout was recorded consistently across every system in the chain: **billing/origin** (Retsuko, Trato Feito, Monopoly, CAP), **payment rail** (Checkout, Vans), **bank evidence** (Itaú statements and/or Nexxera CNAB — francesinha), and **accounting** (SAP via `datalake_pas.ledger`).

**Scope note:** The focus of `datalake_bank_conciliation` is **SAP ↔ Bank** reconciliation — confirming that amounts and dates in the bank (CNAB / Itaú statements) match SAP ledger postings. For **SAP ↔ Product** reconciliation (whether product systems correctly triggered accounting entries), use `business_entities/accounting_funnel.md` instead.

The Data Fintech squad materializes this in the enrich schema **`datalake_bank_conciliation`** (DAG `enrich_bank_conciliation`). There is **no DW layer** for this domain — analysts and FinOps query the enrich tables directly.

**For Rent** (primary stakeholder usage) has three reconciliation types:

1. **For Rent Cashin Collections** — recovered-debt cash-in on account **45268-5** (boleto + Pix via Trato Feito / Retsuko / Checkout).
2. **For Rent Cashin** — regular rental invoice cash-in on account **39221-6** (boleto via Retsuko / Checkout / Vans; Pix / Bolecode available from 2026).
3. **For Rent Cashout** — landlord and third-party payouts across five accounts (42688-7, 7995-2, 43306-5, 50230-7, 50233-1) via CNAB payments + CAP + SAP.

Additional models cover **For Sale** (`for_sale_cashin`), **Quintocred** (`quintocred_cashin`), and **Rental Guarantee PIX** (`rental_guarantee_cashin`). **Credit-card reconciliation** is handled by Simetrik and is **out of scope** for these tables.

Not every transaction achieves full automatic reconciliation. Manual SAP postings without `id_external_payment`, CPF/CNPJ mismatches (For Sale), and chargeback/DV edge cases (Cashout) leave rows with diagnostic columns instead of a clean `is_reconciled = true`.

## Glossary and Synonyms

- **Conciliação bancária** → bank reconciliation; schema `datalake_bank_conciliation`.
- **FinOps / CaR / CaP** → Finance Operations teams consuming these models (For Rent CaR, For Sale CaR, For Rent Cap).
- **Francesinha** → Nexxera CNAB return file ingested into `datalake_nexxera.*` (boleto/payment confirmations).
- **CNAB** → Brazilian banking file format; success codes differ by flow (`occurrence_code = '06'` for cash-in boleto, `'00'` for cash-out paid, `'DV'` for devolução/refund).
- **Boleto** → Bank slip — traditional payment method
- **Bolecode** → Hybrid boleto that can be paid via QR code or barcode
- **company_use / id_company_use** → bank tracking identifier for For Rent cash-in and cash-out (`id_company_use` in `for_rent_cashin` / `for_rent_cashout`).
- **our_number / id_our_number** → number assigned by the bank (Itaú) to the boleto; used as the tracking identifier in For Rent Cashin Collections (`id_our_number` in `for_rent_cashin_collections`; `our_number` column in Checkout / Trato Feito / Nexxera).
- **your_number** → identifier QuintoAndar sends to the bank when registering the boleto (`your_number` column in `datalake_checkout_clean.boleto` / `bolecode`; aligned with `company_use` / `document_number` in other systems).
- **Seu Barriga / Retsuko** → rental billing system (`datalake_retsuko.invoice`).
- **Trato Feito** → collections negotiation platform (`datalake_trato_feito_clean.*`).
- **CAP / payment_platforms** → accounts-payable funnel unifying payout sources (`datalake_accounting_funnel.payment_platforms`).
- **PAS ledger** → SAP-only ledger replica for automated matching (`datalake_pas.ledger`).
- **is_reconciled** → model flag when all per-stage `status_*` columns equal `'ok'` (see reconciliation logic per table).
- **is_bank_concilied_detail** → human-readable reason when reconciliation fails (missing stage, divergent amount/date, SAP duplication).
- **sap_error_detail** → SAP-gateway diagnostic when SAP is missing (`sap_entity`, `sync_sap_job`, `webhook_log`).
- **Simetrik** → external tool for credit-card reconciliation (not modeled here).

## Tables

| You need... | Use this table |
|-------------|----------------|
| Unified For Rent view (Cashin + Collections + Cashout) for FinOps dashboards | UNION of `for_rent_cashin_collections`, `for_rent_cashin`, `for_rent_cashout` — see Golden Query 1 |
| Collections / Trato Feito recovered-debt cash-in (boleto + Pix, account 45268-5) | `datalake_bank_conciliation.for_rent_cashin_collections` |
| Regular rental invoice cash-in (boleto, account 39221-6; Vans legacy + Checkout from Mar/2025) | `datalake_bank_conciliation.for_rent_cashin` |
| Landlord / third-party payouts (5 accounts, DOC/TED/TEF) | `datalake_bank_conciliation.for_rent_cashout` |
| For Sale cash-in (Sinal, Corretagem, ByPass; accounts 45258-6 and 98464-6) | `datalake_bank_conciliation.for_sale_cashin` |
| Quintocred cash-in | `datalake_bank_conciliation.quintocred_cashin` |
| Rental Guarantee PIX cash-in | `datalake_bank_conciliation.rental_guarantee_cashin` |
| Drill into why a row failed reconciliation | `is_bank_concilied_detail` + per-stage `status_*` on the enrich table; `sap_error_detail` when SAP is missing |
| Raw bank statement for a specific Itaú account | `datalake_itau_statements_clean.statement_*` (account-specific table) |
| Raw CNAB boleto returns (rental) | `datalake_nexxera.cnab_charges` — filter `is_last_attempt = TRUE` and `occurrence_code = '06'` |
| Raw CNAB boleto returns (collections) | `datalake_nexxera.cnab_charges_recupera` — same filters |
| Raw CNAB payment returns (cash-out) | `datalake_nexxera.cnab_payments` — `occurrence_code = '00'` (paid) or `'DV'` (refund) |
| SAP ledger postings | `datalake_pas.ledger` |

**Critical rules:**
- Prefer **`is_reconciled`** (and `status_*` breakdown) from the enrich table for operational monitoring; the stakeholder UNION query recomputes **`is_concilied`** from amount/date equality — logic is similar but not identical.
- **Cashout** uses a simpler grain: bank (francesinha) ↔ CAP ↔ SAP; `billing_amount` is NULL in the unified view. Column is spelled **`is_reconcilied`** (typo preserved) on `for_rent_cashout`.
- **For Rent Cashin** has no bank statement yet (boleto-only); Pix rollout in 2026 will require model updates similar to For Sale / Collections.
- CNAB reads must filter **`is_last_attempt = TRUE`** on charge tables to avoid duplicate attempts.
- `is_reconciled = false` on SAP does **not** always mean the payment was not accounted — manual SAP postings without `id_external_payment` are not traceable.

## Key Metrics

- **Reconciliation rate** — `COUNT(*) FILTER (WHERE is_reconciled)` / `COUNT(*)` by `conciliation_type` and month (`dt_bank_paid` or `dt_paid`).
- **Unreconciled volume (amount)** — `SUM(bank_amount)` where `is_reconciled = false`.
- **Gap by stage** — count rows where `status_bank`, `status_billing` / `status_retsuko`, `status_checkout` / `status_vans_checkout`, or `status_sap` ≠ `'ok'`.
- **SAP missing rate** — share with `is_bank_concilied_detail` like `'Not Concilied - SAP missing'` or non-null `sap_error_detail`.
- **Amount divergence** — rows where `ABS(bank_amount) <> ABS(sap_amount)` or billing/checkout amounts differ.
- **Date divergence** — rows where `dt_bank_paid <> dt_sap_paid` (or billing/checkout dates) despite matching amounts.
- **For Sale match rate** — `monopoly_is_reconcilied` and `sap_is_reconcilied` on `for_sale_cashin` by `bank_type_transaction` (PIX vs TED/TEF vs BOLETO).

## Relationships with Other Entities

### Payments (N:1 — reconciliation row validates a payment event)

- Cash-in models join Checkout (`datalake_checkout_clean.boleto`, `bolecode`, `pix`), Vans (`datalake_vans_clean.boleto`), and billing (`datalake_retsuko.invoice`).
- For payment-method analytics and unified charge grain, see `business_entities/payments.md` (`dw_payments_platform.fact_payment`).
- Reconciliation answers "did the paid amount land in bank and SAP?" — payments answers "how was the charge processed?".

### Collections (N:1 — collections cash-in is a subset)

- `for_rent_cashin_collections` tracks Trato Feito installments and Retsuko invoices from debt recovery.
- For negotiation and overdue context, see `business_entities/collections.md` (`dw_collection_recovery_quintoandar.*`).
- Do not confuse with collections operational metrics — bank reconciliation is a **post-payment accounting control**.

### For Sale / FS Transact (N:1 — offer-level cash-in)

- `for_sale_cashin` links Monopoly offers (`sk_offer`, `sk_house`) to bank/SAP via pseudo-IDs (CPF fragment + `id_house`) or Checkout Pix (`id_bank_payment` ↔ `origin_identifier` after Dec/2025).
- For transaction funnel context, see `business_entities/fs-transact.md`.

### SAP / Accounting funnel (1:1 per ledger posting)

- Cash-out reads `datalake_accounting_funnel.payment_platforms` and `datalake_accounting_funnel.ledger`.
- SAP account numbers in models map to Itaú accounts (e.g. 39221-6 → `11004X` in SAP; valid from 2024-01-01).

## Dos and Don'ts

**Do:**
- Start FinOps For Rent analysis from the **three-table UNION** pattern (Golden Query 1) — it is the validated stakeholder view.
- Use **`conciliation_type`** (`'For Rent Cashin Collections'`, `'For Rent Cashin'`, `'Cashout'`) to split logic; Cashout reconciliation checks only bank vs SAP amounts and dates.
- Filter CNAB sources with **`is_last_attempt = TRUE`** and the correct **`occurrence_code`** per flow (`'06'` cash-in boleto, `'00'` cash-out paid, `'DV'` refund).
- Use **`is_bank_concilied_detail`** and **`status_*`** columns to diagnose which stage broke before escalating to product teams.
- Use **`sap_error_detail`** when `status_sap <> 'ok'` to distinguish Retsuko invoice missing, `sap_entity` failure, gateway sync error, or untraceable manual SAP posting.
- For For Sale Pix after 2025-12-09, match via **`id_bank_payment`** (Checkout) ↔ **`origin_identifier`** (Itaú statement), then **`id_business_entity`** ↔ **`sk_offer`** (Monopoly).

**Don't:**
- Don't use these tables for **credit-card** reconciliation — that flow goes through **Simetrik**.
- Don't assume **`is_reconciled = false`** means FinOps did not fix it manually; manual SAP entries without tracking IDs are invisible to automation.
- Don't UNION Cashin and Cashout without adjusting reconciliation rules — Cashout has no `billing_amount` / `dt_billing`.
- Don't read raw `datalake_nexxera.cnab_charges` without **`is_last_attempt = TRUE`** — you will double-count retry attempts.
- Don't confuse **`id_our_number`** (Collections) with **`id_company_use`** (Cashin / Cashout) — they are different tracking keys for different accounts.
- Don't expect 100% For Sale TED/TEF match — pseudo-ID matching from masked CPF + `id_house` has known gaps (CNPJ vs CPF, spouse payments, multiple offers same day).

## Golden Queries

### Query 1 — Unified For Rent reconciliation (FinOps standard view)

Consolidates the three For Rent enrich tables into one analyst-facing view with a computed `is_concilied` flag. Adapt date filters as needed.

```sql
WITH union_all_banks AS (
    SELECT
        id_our_number AS id_external_payment,
        hash,
        bank_number,
        'For Rent Cashin Collections' AS conciliation_type,
        bank_account_number,
        sap_account_number,
        bank_amount,
        billing_amount,
        checkout_amount AS payment_source_amount,
        sap_amount,
        dt_bank_paid,
        dt_billing_paid AS dt_billing,
        dt_checkout_paid AS dt_payment_source,
        dt_sap_paid AS dt_sap_reference
    FROM
        datalake_bank_conciliation.for_rent_cashin_collections

    UNION ALL

    SELECT
        id_company_use AS id_external_payment,
        hash,
        bank_number,
        'For Rent Cashin' AS conciliation_type,
        bank_account_number,
        sap_account_number,
        bank_amount,
        retsuko_amount AS billing_amount,
        vans_checkout_amount AS payment_source_amount,
        sap_amount,
        dt_bank_paid,
        dt_retsuko_paid AS dt_billing,
        dt_vans_checkout_paid AS dt_payment_source,
        dt_sap_paid AS dt_sap_reference
    FROM
        datalake_bank_conciliation.for_rent_cashin

    UNION ALL

    SELECT
        id_company_use AS id_external_payment,
        hash,
        id_company_use AS bank_number,
        'Cashout' AS conciliation_type,
        bank_account_number,
        sap_account_number,
        bank_paid_amount AS bank_amount,
        CAST(NULL AS DECIMAL(12, 2)) AS billing_amount,
        cap_paid_amount AS payment_source_amount,
        sap_paid_amount AS sap_amount,
        dt_bank_paid,
        CAST(NULL AS DATE) AS dt_billing,
        dt_cap_paid AS dt_payment_source,
        dt_sap_paid AS dt_sap_reference
    FROM
        datalake_bank_conciliation.for_rent_cashout
),

df AS (
    SELECT
        *,
        IF(
            ABS(bank_amount) - ABS(sap_amount) = 0
            AND dt_bank_paid = dt_sap_reference,
            'true',
            'false'
        ) AS is_concilied
    FROM
        union_all_banks
    WHERE
        conciliation_type = 'Cashout'

    UNION ALL

    SELECT
        *,
        IF(
            ABS(bank_amount) = ABS(sap_amount)
            AND ABS(bank_amount) = ABS(billing_amount)
            AND ABS(bank_amount) = ABS(payment_source_amount)
            AND dt_bank_paid = dt_sap_reference
            AND dt_bank_paid = dt_billing
            AND dt_bank_paid = dt_payment_source,
            'true',
            'false'
        ) AS is_concilied
    FROM
        union_all_banks
    WHERE
        conciliation_type != 'Cashout'
)

SELECT
    conciliation_type,
    id_external_payment,
    hash,
    bank_number,
    bank_account_number,
    sap_account_number,
    bank_amount,
    billing_amount,
    payment_source_amount,
    sap_amount,
    dt_bank_paid,
    dt_billing,
    dt_payment_source,
    dt_sap_reference,
    is_concilied
FROM
    df
```

### Query 2 — Reconciliation rate by type and month

Uses the model's native `is_reconciled` flag and per-stage status columns.

```sql
SELECT
    'For Rent Cashin Collections' AS conciliation_type,
    DATE_TRUNC('month', dt_bank_paid) AS dt_month,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE is_reconciled) AS reconciled_rows,
    CAST(COUNT(*) FILTER (WHERE is_reconciled) AS DOUBLE) / COUNT(*) AS reconciliation_rate,
    COUNT(*) FILTER (WHERE status_bank != 'ok') AS bank_gaps,
    COUNT(*) FILTER (WHERE status_billing != 'ok') AS billing_gaps,
    COUNT(*) FILTER (WHERE status_checkout != 'ok') AS checkout_gaps,
    COUNT(*) FILTER (WHERE status_sap != 'ok') AS sap_gaps
FROM
    datalake_bank_conciliation.for_rent_cashin_collections
GROUP BY
    1, 2

UNION ALL

SELECT
    'For Rent Cashin',
    DATE_TRUNC('month', dt_bank_paid),
    COUNT(*),
    COUNT(*) FILTER (WHERE is_reconciled),
    CAST(COUNT(*) FILTER (WHERE is_reconciled) AS DOUBLE) / COUNT(*),
    COUNT(*) FILTER (WHERE status_bank != 'ok'),
    COUNT(*) FILTER (WHERE status_retsuko != 'ok'),
    COUNT(*) FILTER (WHERE status_vans_checkout != 'ok'),
    COUNT(*) FILTER (WHERE status_sap != 'ok')
FROM
    datalake_bank_conciliation.for_rent_cashin
GROUP BY
    1, 2

UNION ALL

SELECT
    'For Rent Cashout',
    DATE_TRUNC('month', dt_bank_paid),
    COUNT(*),
    COUNT(*) FILTER (WHERE is_reconcilied),
    CAST(COUNT(*) FILTER (WHERE is_reconcilied) AS DOUBLE) / COUNT(*),
    COUNT(*) FILTER (WHERE is_bank_concilied = false),
    CAST(NULL AS BIGINT),
    CAST(NULL AS BIGINT),
    COUNT(*) FILTER (WHERE sap_error_detail IS NOT NULL)
FROM
    datalake_bank_conciliation.for_rent_cashout
GROUP BY
    1, 2
ORDER BY
    conciliation_type,
    dt_month DESC
```

### Query 3 — Unreconciled rows with failure reason (drill-down)

```sql
SELECT
    id_company_use,
    bank_account_number,
    bank_amount,
    retsuko_amount,
    vans_checkout_amount,
    sap_amount,
    status_bank,
    status_retsuko,
    status_vans_checkout,
    status_sap,
    is_reconciled,
    is_bank_concilied_detail,
    sap_error_detail,
    dt_bank_paid,
    dt_retsuko_paid,
    dt_vans_checkout_paid,
    dt_sap_paid
FROM
    datalake_bank_conciliation.for_rent_cashin
WHERE
    is_reconciled = false
ORDER BY
    dt_bank_paid DESC
```