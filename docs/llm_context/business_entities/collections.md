# Collections

## Overview

Collections is the **operational phase** focused on recovering overdue payments: reminders, outbound contact, restructuring, and negotiations. The debt remains **accounts receivable** (asset) but is flagged as past due until paid, renegotiated, or written off.

- **Objective:** Reduce delinquency and protect cash flow.
- **Asset status:** Still AR on the balance sheet; flagged as overdue.
- **Typical actions:** Email/SMS, calls, deals (acordos), self-service negotiation, advisory (assessoria), legal/eviction tracks.
- **Common metrics:** DSO (days sales outstanding), roll rates between delay buckets, recovery rates, contact KPIs (CPC, ALO, promessas).

Fintech models described here live in **`dw_collection_recovery_quintoandar`**, **`dw_collections_landlord`**, **`dw_collections_segmentation`**, and **`dw_evictions`**. They connect to **losses / AR** models (`dw_losses`) for provisioned vs non-provisioned views and to **rent** (`dw_rent`) for contract attributes.

**Matthew (collection AI agents):** not defined in these four DAGs; interaction flags such as **`has_matthew_interaction`** on the overdue portfolio timeline come from collections QuintoAndar datalake inputs.

## Synonyms

| Term | Meaning |
|------|---------|
| **Cobrança** | Collections |
| **Assessoria** | Third-party advisory collection |
| **Acordo** | Negotiated payment plan (often multiple installments) |
| **Promessa** | Promise to pay (before first installment is paid) |
| **FPD** | First payment default |
| **SSN / BOSSN** | Self-service negotiation flows (see `is_ssn` on overdue timeline) |

## Where to query what

| You need… | Schema / table |
|-----------|----------------|
| Daily overdue invoice timeline, recovery amounts, queues, Flow/Stock | `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline` (+ incremental variant if using partitions) |
| Collection touches (Cyber + Recupera) | `dw_collection_recovery_quintoandar.fact_collection` + `dim_operator` |
| Debt at invoice grain (negotiated deals, sources) | `dw_collection_recovery_quintoandar.fact_debt` |
| Negotiations (status, amounts, classification) | `dw_collection_recovery_quintoandar.fact_negotiation` |
| Negotiation installments (boletos/extra invoices) | `dw_collection_recovery_quintoandar.fact_negotiation_installment` |
| Link invoice-debt ↔ negotiation | `dw_collection_recovery_quintoandar.bridge_map_debt_negotiation` |
| Renegotiation chain / anchor invoice | `dw_collection_recovery_quintoandar.fact_renegotiations` |
| Agencies (Cyber) | `dw_collection_recovery_quintoandar.dim_agency` |
| **Landlord** portfolio: Retsuko invoices, bill-item balances, deals | `dw_collections_landlord.fact_invoice_landlord_portfolio` |
| Original invoice ↔ deal installment match | `dw_collections_landlord.fact_landlord_deal_installment_match` |
| Landlord overdue **daily** timeline (delay T2, contract delay range) | `dw_collections_landlord.fact_overdue_portfolio_timeline` |
| **Tenant / QA** wallet: invoice-day features, T1/T2/T3 delays, bill clusters | `dw_collections_segmentation.fact_invoice_wallet_timeline` |
| Contract-day wallet rollups, income, eviction flag, comms rollups | `dw_collections_segmentation.fact_contract_wallet_timeline` |
| ML-oriented features: frozen **`prob_payment`**, **`segmentation`**, **`tree_class`**, accumulators | `dw_collections_segmentation.fact_contract_features_timeline` |
| **Cyber Legal** eviction case fact (stages, costs, lead times) | `dw_evictions.fact_evictions` |
| Juridical log actions | `dw_evictions.fact_action` |
| Legal alerts | `dw_evictions.fact_alerts` |
| Legal custas / expenses | `dw_evictions.fact_expenses` |
| Formal AR + recovery (PDD universe) | `dw_losses.fact_accounts_receivable` (separate `dw_accounts_receivable` DAG) |

---

## `dw_collection_recovery_quintoandar`

**Purpose:** Collection recovery for QuintoAndar — Recupera, Trato Feito, Seu Barriga / Retsuko, Cyber sources.

**Pipeline:** `query_delta`, layer `dw`, schema **`dw_collection_recovery_quintoandar`**, default **full** extract; UDF **`FINTECH_COLLECTIONS_RENEGOTIATION`** for renegotiation logic. **`fact_overdue_portfolio_timeline_incremental`** is **incremental** with partitions `year, month, day`. Triggered **daily** (Mediator). Inner dependency order: debt + installments + bridge feed negotiations and overdue timeline.

### `fact_collection`

Grain: **one row per collection occurrence** (action on a contract/customer). **`sk_collection`** hashes customer, contract, creditor, operator, action, occurrence time.

| Topic | Fields |
|-------|--------|
| Keys / links | `sk_debtor` (CPF), `sk_contract`, `sk_operator`, `operator_agency` |
| Source | **`source`**: `Cyber` vs `Recupera` |
| Action | `action`, `action_code_type`, `action_description`, `result*`, `complement*`, `total_esforco`, `total_alo`, `total_cpc`, `total_promisse`, `total_agreement`, `total_failure` |
| Time | `dt_occurrence`, `year`, `month`, `day` |

### `fact_debt`

Grain: **invoice × contract** in the recovery model (includes negotiated / not yet due). One invoice can appear in **multiple negotiations** if promises break; one negotiation can cover **multiple invoices**.

Important fields: `sk_debt`, `id_contract`, `id_invoice` (Seu Barriga external id), `creditor`, `payment_status`, `invoice_status` (**open**, **paid**, **written-down**, **canceled**, **not-payable**, **divergent-payment**), `sub_status` (**debt**, **ongoing-negotiation**, …), amounts (`due_amount`, fees, `debt_amount`, `paid_amount`), `source`, dates (`dt_due`, `dt_paid`).

### `fact_negotiation`

Negotiation header from Trato Feito / collections stack: `sk_negotiation`, `sk_contract`, `sk_debtor`, `creditor`, **`negotiation_status`** (started, offset, broken, finished, canceled, …), **`negotiation_classification`** (ACORDO, QUITAÇÃO, SUBSTITUIÇÃO, PROMESSA, PROMESSA QUEBRADA), agreement metadata (`agreement_type`, `advisory`, `origin_agreement`), money fields (discounts, `negotiated_amount`, down payment columns), **`delay_contamined_range`**, installment counts, dates (`dt_promisse`, `dt_due_promisse`, `dt_down_payment`, …), flags `is_renegotiation`, `has_been_renegotiated`.

### `fact_negotiation_installment`

Grain: **one row per installment** of a negotiation. Links to `sk_negotiation`, **`id_invoice_extra`** (Seu Barriga), `installment_number`, `installment_status` (pending, registered, paid, expired, …), amounts and discounts, `payment_method`, dates (`dt_due`, `dt_paid`).

### `bridge_map_debt_negotiation`

Maps **`sk_debt`** ↔ **`sk_negotiation`** when a negotiation exists; **`source`** indicates Trato Feito vs Cyber vs Recupera priority.

### `fact_overdue_portfolio_timeline`

Grain: **invoice × contract × `dt_reference`** (daily while invoice is overdue until paid or written down). Invoice enters **one day after due** and is replicated daily.

| Topic | Examples |
|-------|----------|
| Keys | `sk_overdue_portfolio_timeline`, `id_invoice`, `sk_contract`, `sk_negotiation`, `sk_origin_negotiation` (extra invoices), `sk_agency`, `sk_region` |
| Delays | `delay_invoice_at_reference`, `delay_contamined_range`, **`delay_contract_range`** (contract-level, PDD-related), `delay_first_payment_default`, `delay_contamined_at_closure` |
| Amounts | `due_amount`, `paid_amount`, `recovered_amount`, **`net_recovered_amount`** (adjusts for negotiation net rate on written-down), `contract_debt` |
| Ops / routing | `recovery_channel`, **`debtor_type`** (**Flow** = new in month vs **Stock**), `advisory`, **`segmentation_queue`**, **`agreement_queue`**, **`eviction_queue`** (+ descriptions), `has_matthew_interaction`, `has_app_action_event`, **`is_ssn`**, `is_most_recent_record_month`, `is_last_business_days` |
| Dates | `dt_reference`, `dt_month_start`, `dt_month_end`, `dt_invoice_due`, `dt_invoice_paid`, `dt_write_off` |

Use **`is_most_recent_record_month = true`** for **one row per invoice per month** when deduplicating to the latest day in the month.

### `fact_renegotiations`

Anchor invoice per renegotiation hierarchy: `sk_contract`, `sk_invoice`, `sk_anchor_invoice`, `renegotiation_level`, parent/child negotiation keys, `dt_due_adjusted_anchor`.

### Dimensions

- **`dim_agency`**: Cyber agency groups (`sk_agency`, `main_agency_name`, …).
- **`dim_operator`**: Normalized operators (Recupera, Cyber, Paschoalotto, Webhelp, etc.).

---

## `dw_collections_landlord`

**Purpose:** Collections analytics for **landlord-side** invoices (Retsuko **`invoice_user`** landlord), bill-item decomposition, and **deal installment** matching.

**Pipeline:** `query_delta`, schema **`dw_collections_landlord`**, full load. **`fact_landlord_deal_installment_match`** depends on **`fact_invoice_landlord_portfolio`**; **`fact_overdue_portfolio_timeline`** depends on the match table.

### `fact_invoice_landlord_portfolio`

Landlord invoice spine: `id_invoice`, `id_contract`, **`tipo_fat`** (original vs deal), status/payment fields, **`list_bill_items`**, **`due_amount` / `due_amount_adjustment`**, per–bill-item **`balance_*`** and **`has_bi_*`** flags (adm fee, rental core, repair, collections deal, etc.), lifecycle dates (`dt_begin`, `dt_end`, `dt_due`, …).

### `fact_landlord_deal_installment_match`

Links **`id_invoice_original`** ↔ **`id_invoice_deal`** with deal status, amounts, dates, **`rn_deal_order`**.

### `fact_overdue_portfolio_timeline`

Landlord daily timeline: delay flags (**`flag_delay`**, **`flag_delay_t1`**, **`delay_t2`**), **`invoice_status_timeline`**, **`invoice_life_status_timeline`**, deal match fields, **`recovered_amount`**, **`delay_range_contract_t2`**, **`max_delay_t2_contract_level`**, **`last_contract_delay_at_closing`**, plus inherited portfolio columns from landlord `fact_invoice_landlord_portfolio`.

---

## `dw_collections_segmentation`

**Purpose:** **Wallet segmentation** and **delay methodologies (T1 / T2 / T3)** for collections operations and modeling.

**Pipeline:** `query_delta`, schema **`dw_collections_segmentation`**, default **incremental** with partitions **`year, month, day`** and rolling **`load_start_date` / `load_end_date`**. Build order: **`fact_invoice_wallet_timeline`** → **`fact_contract_wallet_timeline`** → **`fact_contract_features_timeline`**.

### Delay methodologies (high level)

- **T1:** Baseline invoice delay (simpler contamination).
- **T2:** Delay with **deal / negotiation contamination** (aligns with many operational roll metrics).
- **T3:** Contract-level contamination variants used for **wallet / losses** views (see `*_t3*`, `*_t3_losses*` columns on contract timeline).

### `fact_invoice_wallet_timeline`

Daily **invoice** grain: `id_contract`, `id_invoice`, negotiation parent/child ids, **`is_invoice_overdue_t1/t2/t3`**, **`invoice_delay_t1/t2/t3`**, **`contract_delay_t1/t3`**, recovery channel fields, **bill-item presence and balances** (condomínio, multa rescisória, acordo, rental core, reparos, …), wallet ordering (`order_invoice_wallet_risk`, `order_invoice_wallet recovered_amount*` / on-time paid splits by T*, `dt_reference`, `dt_due`, anchor dates.

### `fact_contract_wallet_timeline`

Daily **contract** grain: aggregates from invoice wallet — max delays (`max_delay_contaminated_contract_t1/t2`, `max_delay_original_invoices_t1/t2`, `max_delay_deal_invoices_t1/t2`, T3 variants), counts of overdue monthly/deal/other invoices, **open wallet** and **wallet** amounts by T*, **debts_in_income_share**, **cpc** / **alo** from `fact_collection`, app event counts, **promessas**, broken agreement counters, **`id_process_evictions`** / **`is_evictions`**, bill-cluster counts and open balances, **`rent` / `condo` / `iptu` / `package_amount`** from `dim_contract`, arrays of open/paid/negotiated invoices, FPD / negativable flags, **`monthly_income`**, partition columns.

### `fact_contract_features_timeline`

Subset of wallet timeline plus **accumulated** features (`acc_*`), **rolling** windows (e.g. L12M, L90, L180), **`tree_class`** and **frozen** **`prob_payment`** (vs volatile `prob_payment_at_dt_reference`), **`segmentation`** vs **`segmentation_with_prob_payment_at_dt_reference`**, **`macro_segmentation`** / **`next_macro_segmentation`** / transition flags, **`segment_comms`**, delay buckets **`t1_delay_bucket`** / **`t2_delay_bucket`**, broken-deal flags (`flag_broken_installment_deal`, …). Designed for **stable monthly segmentation** once a contract enters a decision-tree class.

---

## `dw_evictions`

**Purpose:** **Cyber Legal** eviction and related operational facts (not the same as collections queue flags alone).

**Pipeline:** `query_delta`, schema **`dw_evictions`**, full load.

### `fact_evictions`

Case-level fact: `sk_process`, `sk_contract`, office/agency/court/region/city, `cyber_status`, `last_stage`, **per-stage expense totals**, passage/result fields, **`contract_category_at_registration`** and **`overdue_days_at_registration`** (from **`fact_contract_wallet_timeline`**), lead times (`ldt_stock`, `ldt_resolution`, `real_ldt_resolution`, many **`ldt_*`** stage SLAs using business days), extensive **stage start/end dates**, financial totals, flags (`is_reincident`, `is_reopened`, …).

### `fact_action`

Juridical log: `sk_case`, `contract`, `action` / `result` / `complement` codes and descriptions, `ts_activity`.

### `fact_alerts`

Cyber alerts: `sk_alert`, `sk_case`, contract ids, alert type/review/task/aging, dates.

### `fact_expenses`

Custas / expenses by case and stage: amounts, authorization/reimbursement flags, attorney ids, dates.

---

## Relationships with other entities

- **Invoice ↔ contract:** `id_invoice` / `sk_contract` align with **`dw_losses`** and **`dw_rent.dim_contract`** / Retsuko ids.
- **Overdue timeline ↔ AR:** Invoices **on PDD** appear in **`dw_losses.fact_accounts_receivable`**; invoices **not yet** in that universe can still appear in **`fact_overdue_portfolio_timeline`** — union patterns are common for full AR recovery metrics (see golden query).
- **Negotiations:** Join **`fact_negotiation`** to **`fact_negotiation_installment`** and **`bridge_map_debt_negotiation`** / **`fact_debt`** for invoice-level detail.
- **Evictions:** Link **`dw_evictions.fact_evictions.sk_contract`** to contract timelines; **`fact_contract_wallet_timeline.is_evictions`** / **`id_process_evictions`** aligns operational segmentation with cases.
- **Losses:** For provisioned delay buckets use **`dw_losses.fact_delay`** / **`fact_provision`**; for operational delay buckets use collections timeline fields (`delay_contamined_range`, `delay_contract_range`, wallet T2/T3).

## Dos and don'ts

**Do:**

- For month-end dashboard cuts on **`fact_overdue_portfolio_timeline`**, confirm whether the metric needs **`is_most_recent_record_month = true`**.
- When mixing AR and pre-PDD invoices, document whether **`net_recovered_amount`** vs **`recovered_amount`** is required (negotiation-adjusted written-down logic).
- For **`dw_collections_segmentation`**, specify **T1 vs T2 vs T3** explicitly — column names encode the methodology.
- Join **`fact_evictions`** to contracts for legal context; use **`fact_action`** / **`fact_alerts`** for operational follow-up granularity.

**Don't:**

- Confuse schema names: recovery DW is **`dw_collection_recovery_quintoandar`** (not `dw_collections_recovery_quintoandar`).
- Assume landlord table YAML always lists the right `database_name` — DAG **`dw_collections_landlord`** outputs to **`dw_collections_landlord`**.

## Golden query: AR recovery rate (C&E / Neotribe-style)

Consolidates **`dw_losses.fact_accounts_receivable`** with overdue invoices **not** yet on that table for the same month, using **`dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`** and optional **`dw_losses.fact_delay`** for contaminated range. Fix schema names to match production (`dw_collection_recovery_quintoandar`).

```sql
WITH fact_ar_consolidated AS (
    SELECT
        sk_invoice,
        delay_contamined_range AS delay_range,
        invoice_amount AS due_amount,
        COALESCE(net_recovered, 0) AS net_recovered_amount,
        date_add('day', -1, date_trunc('month', dt_month_recovery)) AS dt_closing
    FROM dw_losses.fact_accounts_receivable

    UNION ALL

    SELECT
        a.id_invoice,
        COALESCE(c.delay_contamined_range, a.delay_contract_range),
        a.due_amount,
        COALESCE(a.net_recovered_amount, 0),
        COALESCE(c.dt_closing, date_add('day', -1, a.dt_month_start))
    FROM dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline AS a
    LEFT JOIN dw_losses.fact_accounts_receivable AS b
        ON a.id_invoice = b.sk_invoice
        AND last_day_of_month(b.dt_month_recovery) = a.dt_month_end
    LEFT JOIN dw_losses.fact_delay AS c
        ON a.sk_contract = c.sk_contract
        AND date_add('day', -1, a.dt_month_start) = c.dt_closing
    WHERE b.sk_invoice IS NULL
      AND a.is_most_recent_record_month = true
)

SELECT
    date_trunc('day', CAST(dt_closing AS TIMESTAMP)) AS dt_closing,
    CASE
        WHEN delay_range IN ('a. Current', 'b. 1-30', 'c. 31-60', 'd. 61-90') THEN 'AR 0-90'
        ELSE 'AR 90+'
    END AS okr_bucket,
    SUM(net_recovered_amount) / NULLIF(SUM(due_amount), 0) AS ar_recovery_rate
FROM fact_ar_consolidated
WHERE dt_closing BETWEEN last_day_of_month(date_add('month', -13, current_date))
                    AND last_day_of_month(date_add('month', -1, current_date))
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

**Note:** Exact **`delay_range`** string values must match your environment (losses vs collections naming). Adjust date functions if your engine uses different syntax than Presto/Trino-style `date_add` / `last_day_of_month`.
