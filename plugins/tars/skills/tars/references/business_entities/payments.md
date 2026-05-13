# Payments

## Overview

Payments is the **transactional domain** that tracks every charge processed through QuintoAndar's payment platform — from creation to settlement, refund, or cancellation. The **primary system is Checkout**, which orchestrates the majority of payment transactions across all methods. The `payment_method` field identifies the instrument used:

| Payment method | What it is |
|----------------|-----------|
| **BOLETO** | Traditional Brazilian bank slip — the most common method, especially for rental invoices |
| **CREDIT_CARD** | Credit-card transactions processed via acquirers (Getnet/Wall Street) |
| **PIX** | Instant payment via the Brazilian Central Bank's PIX system |
| **BOLECODE** | Hybrid boleto+code instrument — can be further split into **BOLECODE - QRCODE** (paid via QR code, effectively a PIX payment) and **BOLECODE - BARCODE** (paid via barcode), resolved by joining `datalake_checkout_clean.charge.paid_via` |

Payment data flows through **three independent source systems**:

| Source | What it handles |
|--------|----------------|
| **Checkout** | Primary payment orchestrator — boletos, bolecodes, credit cards, PIX |
| **Wall Street** | Credit-card acquirer hub (Getnet integration), chargebacks, subscriptions |
| **Vans** | VAN (Value Added Network) — boleto exchange with banking agents (Itaú, BB, etc.) |

These sources are unified into `datalake_payments_platform` (enrich) and then consolidated into `dw_payments_platform` (DW), which produces the main analytical tables: `fact_payment` and `fact_payment_timeline`.

**Key lifecycle:** A payment starts with an **order/charge creation**, transitions through processing states (open → processing → paid / error / canceled), and may later undergo **refunds** or **chargebacks** (Wall Street credit-card path only).

## Synonyms

| Term | Meaning |
|------|---------|
| **Pagamento** | Payment |
| **Cobrança** (in checkout context) | Charge (`charge` table in Checkout / Wall Street) |
| **Boleto** | Bank slip — traditional payment method |
| **Bolecode** | Hybrid boleto that can be paid via QR code or barcode |
| **Cartão de crédito** | Credit card |
| **PIX** | Instant payment via Central Bank |
| **Checkout** | Primary payment orchestrator system |
| **Wall Street** | Credit-card acquirer integration hub |
| **Vans** | VAN service — banking file exchange system |
| **Chargeback**, **contestação** | Disputed credit-card transaction (Wall Street) |
| **Trato Feito** | Collections negotiation system — appears as `system_origin` on payments |
| **Seu Barriga / Seubarriga** | Retsuko billing system — main rental invoice payment requester |
| **Requester**, **solicitante** | System that originated the payment request (`id_requester`) |
| **Acordo** | Negotiated deal — creates extra invoices paid through checkout |

## Tables

| You need… | Use this table |
|-----------|----------------|
| Unified payment fact (all sources, all methods) | `dw_payments_platform.fact_payment` |
| Payment status timeline (state transitions over time) | `dw_payments_platform.fact_payment_timeline` |
| Enrich-layer unified payment | `datalake_payments_platform.payment` |
| Enrich-layer payment timeline | `datalake_payments_platform.payment_timeline` |
| Checkout charges | `datalake_checkout_clean.charge` |
| Checkout credit-card transactions | `datalake_checkout_clean.credit_card` |
| Checkout credit-card capture attempts | `datalake_checkout_clean.credit_card_capture_attempt` |
| Checkout boletos / bolecodes | `datalake_checkout_clean.boleto` / `datalake_checkout_clean.bolecode` |
| Checkout PIX transactions | `datalake_checkout_clean.pix` |
| Checkout orders | `datalake_checkout_clean.order` |
| Wall Street charges (credit card) | `datalake_wall_street_clean.charge` |
| Wall Street chargeback notifications | `datalake_wall_street_clean.chargeback_notification` |
| Wall Street invoices / subscriptions | `datalake_wall_street_clean.invoice` / `subscription` / `subscription_item` |
| Wall Street stores (requester mapping) | `datalake_wall_street_clean.store` |
| Vans boletos (bank slips) | `datalake_vans_clean.boleto` |
| Vans boleto-file links | `datalake_vans_clean.boleto_file` / `datalake_vans_clean.file` |
| Vans bank payments | `datalake_vans_clean.bank_payment` / `bank_payment_requested_by` |
| Banking file payments | `dw_payment.fact_banking_file_payments` / `dim_banking_file_payment` |
| Rental payment analytics | `dw_rental_payments.fact_invoice_status_changes` / `dim_bill_item` |
| Getnet return codes (error mapping) | `datalake_gsheets_clean.getnet_return_codes` |
| Debt-recovery negotiations (for `system_origin` resolution) | `datalake_debt_recovery.negotiation` |

### Key columns in `fact_payment`

Grain: **one row per payment** (deduplicated by `id_business_key`).

| Column | Description |
|--------|-------------|
| `sk_payment` | Surrogate key (= `id_payment` from enrich) |
| `id_business_key` | Business key |
| `id_charge`, `id_order` | Charge and order identifiers |
| `id_contract`, `id_person`, `id_invoice`, `id_finance_entity` | Entity links |
| `id_requester`, `requester_description` | System that originated the payment |
| `id_acquire_transaction`, `acquirer_auth_code`, `acquire_nsu`, `acquire_return_code` | Acquirer details |
| `payment_status` | Current status |
| `successfull_method` | Payment method that succeeded |
| `datasource` | Source system (`checkout`, `wallstreet`, `vans`) |
| `transaction_category` | Transaction type |
| `methods` | Array of attempted payment methods |
| `status_reason`, `retry_reason`, `error_type` | Error and retry details |
| `installments` | Number of installments (credit card) |
| `due_amount`, `installment_fee_amount`, `fine_amount` | Amounts |
| `method_created_to_paid_latency_seconds` | Time from method creation to payment |
| `is_recurrence`, `has_retry` | Flags |
| `our_number`, `your_number`, `company_use` | Boleto references |
| `dt_due` | Due date |
| `ts_method_created`, `ts_method_paid`, `ts_order_created` | Timestamps |
| `ts_charge_started_processing`, `ts_charge_paid`, `ts_charge_canceled` | Timestamps |

### Key columns in `fact_payment_timeline`

Grain: **one row per payment × timeline step** (state transition).

| Column | Description |
|--------|-------------|
| `sk_payment_timeline` | Surrogate key |
| `sk_payment` | Payment surrogate key |
| `id_business_key`, `id_finance_entity` | Business identifiers |
| `datasource` | Source system |
| `timeline_status` | Status at this step |
| `payment_method_timeline` | Payment method at this step |
| `timeline_order` | Ordinal position in the timeline |
| `timeline_timestamp` | When this transition occurred |

Use `MAX(timeline_order)` grouped by `sk_payment` and `payment_method_timeline` to find the **last known payment method** for a given payment — this is the pattern used in the golden query's `max_timeline_checkout` CTE.

### Key columns in Checkout clean tables

- **`charge`** — payment charge header; `paid_via` distinguishes BARCODE vs QRCODE for bolecodes
- **`credit_card`** — card-level details: `card_brand`, `block_entity`, `cancellation_reason`, `convenience_fee_amount`, `refund_amount`, `acquire_fee_amount`, `interest_amount_percentage`, `installments`
- **`credit_card_capture_attempt`** — capture attempt with `code`, `status`, `installment_fee_amount`
- **`boleto`** / **`bolecode`** — boleto and bolecode instruments with amounts and status
- **`pix`** — PIX payments
- **`order`** — parent order grouping charges

### Key columns in Wall Street clean tables

- **`charge`** — credit-card charge: `charge_status`, `card_brand`, `amount` (stored in **cents** — divide by 100), `refund_amount`, `acquire_fee_percentage`, `acquire_return_code`
- **`chargeback_notification`** — disputed transactions: `reason_code`, `chargeback_amount`, `dt_request`, `dt_return`
- **`invoice`** — invoice linked to charges (with `ts_due`)
- **`store`** — requester store mapping (`description` = requester name)
- **`subscription`** / **`subscription_item`** — recurring subscription management

### Key columns in Vans clean tables

- **`boleto`** — bank slip: `status` (`:boleto.status/*` format), `requested_by`, `due_amount`, `paid_amount`, `company_use` (contains `id_contract`), `related_document_type`, `id_related_document` (maps to `id_finance_entity` when type = `invoice`)
- **`boleto_file`** / **`file`** — links boletos to banking files (filter `file.type = ':file.type/boleto'`)
- **`bank`** / **`bank_payment`** / **`bank_payment_requested_by`** — bank and payment routing configuration

### Payment status normalization

Raw statuses vary by source. The golden query normalizes them to a unified set:

| Unified status | Raw statuses mapped |
|----------------|---------------------|
| **PAID** | `PAID`, `CAPTURED` |
| **PROCESSING** | `PENDING_REGISTER_PAYMENT`, `PROCESSING_REFUND`, `PENDING_CAPTURE`, `PENDING_CANCELATION` |
| **WRITTEN_DOWN** | `WRITTEN_DOWN`, `WRITTEN_DOWN_ERROR`, `WRITE_DOWN_PAID_REQUESTED`, `WRITE_DOWN_REQUESTED` |
| **OPEN** | `REQUESTED`, `CREATED`, `CHANGED` |
| **CHARGEBACK** | `CHARGEBACK_CAPTURED` |
| **ERROR** | `CAPTURE_DENIED`, `CAPTURE_BLOCKED`, `CAPTURE_NOT_PROCESSED`, `CANCELATION_NOT_PROCESSED` |
| **CANCELED** | `CANCELED` (pass-through) |
| **REFUNDED** | `REFUNDED` (pass-through) |

Vans boleto statuses follow `:boleto.status/*` format and are mapped in the query (e.g., `:boleto.status/paid` → `PAID`).

### Product origin mapping

The `product_origin` field groups payments by the **internal system or product** that originated the charge. QuintoAndar operates multiple products, each with its own payment flows — this field normalizes the raw `system_origin` into a business-friendly category:

| Product origin | What it is | `system_origin` values |
|----------------|-----------|------------------------|
| **Rental** | Core rental invoice payments (monthly rent charges) | `seubarriga`, `seubarriga-checkout`, `rent-invoice-payment`, `rental-recurrent-creditcard-payment` |
| **Rental Offer** | Payments related to rental proposals/offers | `rental-offer`, `rental-offer-checkout` |
| **Rental Guarantee** | Guarantee deposits and insurance payments | `pro-guarantor-checkout`, `pro-guarantor`, `rental-guarantee` |
| **Collections** | Debt recovery and negotiation payments (Trato Feito, Cyber, etc.) | `trato-feito`, `trato-feito-cyber`, `trato-feito-5a-collector`, `collections`, `seumadruga` |
| **Reservation** | Reservation-stage payments | `reservation` |
| **Quintocred** | QuintoAndar's credit/guarantee platform | `rental-guarantee-platform` |
| **monopoly** | Other internal systems not mapped above | Falls through the `ELSE system_origin` clause |

Recurrent payments: `system_origin = 'rental-recurrent-creditcard-payment'` → `is_recurrent = 'recurrent'`; all others → `'one time'`.

## Key Metrics

- **Transaction volume** — count of payments by method, status, product origin
- **Success rate** — `PAID` / total transactions (exclude `OPEN` / `PROCESSING` for settled-only views)
- **Payment method distribution** — share of BOLETO, CREDIT_CARD, BOLECODE, PIX
- **Average payment latency** — `method_created_to_paid_latency_seconds` by method
- **Credit-card fee margin** — `convenience_fee_amount + installment_fee_amount - acquire_fee_amount` = `total_cc_fee_amount`
- **Chargeback rate** — chargebacks / total credit-card transactions (Wall Street source)
- **Refund amount** — total refunds by period and product origin
- **Payment punctuality** — `diff_days = date_diff('day', dt_business_due, dt_charge_paid)`; segmented as "paid until due date" / "paid late" / "not paid"
- **Payment segmentation** — timing buckets: 8d+ early, 3–7d early, 2d early, 1d early, on time, 1d+ late

## Relationships with Other Entities

### Contract (N:1 — many payments to one contract)

`id_contract` / `id_business_entity` links to `dw_rent.dim_contract`. Checkout uses `id_contract` directly; Vans extracts it from `company_use` via `regexp_extract(company_use, '^[0-9]+', 0)`.

### Invoice / Finance entity (N:1 — many payments to one invoice)

`id_finance_entity` links to Retsuko invoice IDs (`dw_losses`, `dw_collection_recovery_quintoandar`). Checkout and Wall Street join on `id_finance_entity`; Vans maps `id_related_document` when `related_document_type = 'invoice'`.

### Collections (N:1 — payments originated from debt recovery)

Payments with `id_requester = '3'` originate from Trato Feito (collections). Join `datalake_debt_recovery.negotiation` on `id_contract = id_negotiation` to resolve `collector` and derive `system_origin`.

### Chargebacks (1:N — one charge may have chargeback notifications)

Wall Street only — join `datalake_wall_street_clean.chargeback_notification` on `id_charge` for dispute details (`reason_code`, `chargeback_amount`).

### Losses / AR

Payment status feeds into `dw_losses.fact_accounts_receivable` for provisioning and recovery tracking.

## Dos and Don'ts

**Do:**

- Use `dw_payments_platform.fact_payment` as the starting point for payment analytics — it unifies all three sources
- Apply `ROW_NUMBER() OVER (PARTITION BY id_charge, id_order, id_contract ORDER BY ts_method_created DESC) = 1` when deduplicating checkout data at the charge level
- Use `dt_business_due` (weekend-adjusted) instead of raw `dt_due` for punctuality metrics — weekends are shifted to the next Monday
- Distinguish BOLECODE sub-types: join `datalake_checkout_clean.charge.paid_via` to split into `BOLECODE - QRCODE` vs `BOLECODE - BARCODE`
- Filter `id_requester NOT IN ('4', '10')` to exclude internal/test requesters from production analytics
- Filter Vans boletos with `requested_by = 'seubarriga'` AND `related_document_type = 'invoice'` AND `file.type = ':file.type/boleto'` to get only valid rental invoice boletos
- Use `MAX(timeline_order)` from `fact_payment_timeline` to resolve the last known payment method when `successfull_method` is NULL
- Filter Wall Street subscriptions out: exclude charges that match `subscription.code || '|default-item'` or `subscription.code || '_item'` patterns (these are subscription-management records, not payment transactions)

**Don't:**

- Don't FULL OUTER JOIN Checkout and Wall Street without the correct join key: the join is on `id_finance_entity` AND `code` (Checkout's `captured_status.code` = Wall Street's `charge.code`)
- Don't assume `datasource` values are lowercase everywhere — DW uses `checkout` / `wallstreet` / `vans`; verify casing in the layer you query
- Don't confuse `due_amount` (what was owed) with `paid_amount` (what was actually paid) — they differ when partial payments or fees apply
- Don't mix Vans and Checkout boleto data without the UNION pattern shown in the golden query — Vans boletos are NOT in `fact_payment` by default in some contexts and need explicit union
- Don't forget that `chargeback_amount`, `chargeback_reason`, and chargeback dates come **only from Wall Street** — Checkout and Vans do not have chargeback data
- Don't compute `diff_days` on raw `dt_due` — always use `dt_business_due` to account for weekend adjustments

## Golden Queries

### Query 1 — Successful transactions by payment method (all sources)

Consolidates Checkout + Wall Street + Vans into a unified payment base with normalized statuses, product origins, fee calculations, and payment punctuality segmentation.

```sql
WITH max_timeline_checkout AS (
  SELECT
    sk_payment,
    payment_method_timeline,
    MAX(timeline_order) AS tl_order
  FROM
    dw_payments_platform.fact_payment_timeline
  GROUP BY 1, 2
),

checkout_base AS (
  SELECT
    CAST(fp.id_charge AS VARCHAR(20)) AS id_charge,
    fp.id_order,
    fp.id_contract AS id_business_entity,
    fp.id_finance_entity,
    fp.id_requester,
    fp.payment_status,
    CASE
      WHEN fp.successfull_method IS NULL THEN mtc.payment_method_timeline
      WHEN fp.successfull_method = 'BOLECODE' AND c.paid_via = 'BARCODE' THEN 'BOLECODE - BARCODE'
      WHEN fp.successfull_method = 'BOLECODE' AND c.paid_via = 'QRCODE' THEN 'BOLECODE - QRCODE'
      ELSE fp.successfull_method
    END AS payment_method,
    CASE
      WHEN fp.id_requester = '3' AND n.collector IS NULL THEN 'trato-feito'
      WHEN fp.id_requester = '3' THEN CONCAT('trato-feito', '-', LOWER(n.collector))
      ELSE fp.requester_description
    END AS system_origin,
    fp.error_type,
    fp.due_amount,
    cc.card_brand,
    cc.block_entity,
    cc.cancellation_reason,
    cc.convenience_fee_amount,
    cc.refund_amount,
    cc.acquire_fee_amount,
    c.paid_amount,
    cc.interest_amount_percentage,
    cc.installments,
    cca.code,
    cca.status AS captured_status,
    cca.installment_fee_amount,
    fp.method_created_to_paid_latency_seconds,
    fp.dt_due,
    CASE
      WHEN day_of_week(fp.dt_due) = 6 THEN date_add('day', 2, fp.dt_due)
      WHEN day_of_week(fp.dt_due) = 7 THEN date_add('day', 1, fp.dt_due)
      ELSE fp.dt_due
    END AS dt_business_due,
    fp.ts_method_created,
    fp.ts_charge_paid,
    fp.ts_charge_canceled,
    fp.datasource,
    ROW_NUMBER() OVER (
      PARTITION BY fp.id_charge, fp.id_order, fp.id_contract
      ORDER BY fp.ts_method_created DESC
    ) AS rn
  FROM
    dw_payments_platform.fact_payment fp
  LEFT JOIN max_timeline_checkout mtc
    ON fp.sk_payment = mtc.sk_payment
  LEFT JOIN datalake_debt_recovery.negotiation AS n
    ON fp.id_contract = n.id_negotiation
  LEFT JOIN datalake_checkout_clean.charge AS c
    ON c.id = fp.id_charge
  LEFT JOIN datalake_checkout_clean.credit_card AS cc
    ON fp.id_charge = cc.id_charge
  LEFT JOIN datalake_checkout_clean.credit_card_capture_attempt AS cca
    ON cc.id = cca.id_credit_card
  WHERE datasource = 'checkout'
    AND DATE(ts_order_created) >= DATE('2024-10-01')
),

wallstreet_base AS (
  SELECT
    CAST(wsc.id AS VARCHAR(20)) AS id_charge,
    wsc.id_store,
    wsc.id_acquire_transaction,
    wsc.id_business_entity,
    COALESCE(wsc.id_finance_entity, wssi.code) AS id_finance_entity,
    wscn.id AS id_chargeback,
    wss.description AS requester_name,
    wsc.charge_status,
    wsc.code,
    wsc.risk_entities,
    wsc.installments,
    wsc.acquire_message,
    wsc.acquire_return_code,
    COALESCE(grc.description, 'NAO IDENTIFICADO') AS acquire_error_type,
    wscn.reason_code,
    CASE
      WHEN wscn.reason_code IN ('4837', '104', '83') THEN 'Fraude'
      WHEN wscn.reason_code IN ('4853', '131', '4860') THEN 'Desacordo Comercial'
      WHEN wscn.reason_code IN ('4831', '1262', '4834') THEN 'Erro de processamento'
      ELSE NULL
    END AS chargeback_reason,
    wscn.message,
    wsc.card_brand,
    'CREDIT_CARD' AS payment_method,
    CAST(wsc.amount AS DECIMAL(10,2)) / 100 AS amount,
    CAST(wsc.refund_amount AS DECIMAL(10,2)) / 100 AS refund_amount,
    (wsc.acquire_fee_percentage * CAST(wsc.amount AS DECIMAL(10,2)) / 100) AS acquire_fee_amount,
    CAST(wscn.chargeback_amount AS DECIMAL(10,2)) / 100 AS chargeback_amount,
    wscn.dt_request AS dt_chargeback_requested,
    wscn.dt_return AS dt_chargeback_processed,
    wsi.ts_created,
    wsi.ts_due,
    CASE
      WHEN day_of_week(DATE(wsi.ts_due)) = 6 THEN date_add('day', 2, DATE(wsi.ts_due))
      WHEN day_of_week(DATE(wsi.ts_due)) = 7 THEN date_add('day', 1, DATE(wsi.ts_due))
      ELSE DATE(wsi.ts_due)
    END AS dt_business_due,
    wsc.ts_paid,
    wsc.ts_updated,
    'wallstreet' AS datasource,
    ROW_NUMBER() OVER (
      PARTITION BY wsc.id, wsc.id_business_entity
      ORDER BY wsc.ts_updated DESC
    ) AS rn
  FROM
    datalake_wall_street_clean.charge AS wsc
  INNER JOIN datalake_wall_street_clean.store AS wss
    ON wsc.id_store = wss.id
  LEFT JOIN datalake_wall_street_clean.invoice AS wsi
    ON wsc.id = wsi.id_charge
  LEFT JOIN datalake_gsheets_clean.getnet_return_codes AS grc
    ON grc.new_code = wsc.acquire_return_code
    AND IF(grc.card_brand = 'GETNET' OR grc.card_brand = 'TODAS', 1 = 1, grc.card_brand = UPPER(wsc.card_brand))
  LEFT JOIN datalake_wall_street_clean.chargeback_notification AS wscn
    ON wsc.id = wscn.id_charge
  LEFT JOIN datalake_wall_street_clean.invoice_subscription_item AS wsisi
    ON wsisi.id_invoice = wsi.id
  LEFT JOIN datalake_wall_street_clean.subscription_item AS wssi
    ON wssi.id = wsisi.id_subscription_item
  LEFT JOIN datalake_wall_street_clean.subscription AS s
    ON wssi.code = (s.code || '|default-item')
  LEFT JOIN datalake_wall_street_clean.subscription AS s1
    ON wssi.code = (s1.code || '_item')
  WHERE
    s.code IS NULL
    AND s1.code IS NULL
    AND DATE(wsc.ts_updated) >= DATE('2024-01-01')
),

vans_base AS (
  SELECT
    CAST(b.id AS VARCHAR(20)) AS id_charge,
    NULL AS id_order,
    regexp_extract(b.company_use, '^[0-9]+', 0) AS id_business_entity,
    CAST(IF(related_document_type = 'invoice',
      COALESCE(CAST(id_related_document AS BIGINT), -1), -1) AS VARCHAR(20)) AS id_finance_entity,
    '5' AS id_requester,
    NULL AS id_chargeback,
    CASE
      WHEN b.status = ':boleto.status/paid' THEN 'PAID'
      WHEN b.status = ':boleto.status/error' THEN 'ERROR'
      WHEN b.status = ':boleto.status/requested' THEN 'REQUESTED'
      WHEN b.status = ':boleto.status/written-down' THEN 'WRITTEN_DOWN'
      WHEN b.status = ':boleto.status/created' THEN 'CREATED'
      WHEN b.status = ':boleto.status/write-down-paid-requested' THEN 'WRITE_DOWN_PAID_REQUESTED'
      WHEN b.status = ':boleto.status/write-down-requested' THEN 'WRITE_DOWN_REQUESTED'
      WHEN b.status = ':boleto.status/changed' THEN 'CHANGED'
      WHEN b.status = ':boleto.status/written-down-error' THEN 'WRITTEN_DOWN_ERROR'
      ELSE b.status
    END AS payment_status,
    'BOLETO' AS payment_method,
    b.requested_by AS system_origin,
    b.due_amount,
    b.paid_amount,
    NULL AS refund_amount,
    NULL AS chargeback_amount,
    NULL AS convenience_fee_amount,
    NULL AS acquire_fee_amount,
    NULL AS installment_fee_amount,
    NULL AS installments,
    NULL AS card_brand,
    CASE
      WHEN b.occurrence_reason = 'ENTRADA REJEITADA' THEN 'ENTRADA REJEITADA'
      ELSE NULL
    END AS error_type,
    NULL AS acquire_message,
    NULL AS chargeback_reason,
    NULL AS method_created_to_paid_latency_seconds,
    DATE(b.ts_created) AS dt_method_created,
    b.dt_due,
    CASE
      WHEN day_of_week(b.dt_due) = 6 THEN date_add('day', 2, b.dt_due)
      WHEN day_of_week(b.dt_due) = 7 THEN date_add('day', 1, b.dt_due)
      ELSE b.dt_due
    END AS dt_business_due,
    b.dt_paid AS dt_charge_paid,
    CASE
      WHEN b.status = ':boleto.status/canceled' THEN DATE(b.ts_updated)
      ELSE NULL
    END AS dt_canceled,
    NULL AS dt_chargeback_requested,
    NULL AS dt_chargeback_processed,
    'vans' AS datasource,
    ROW_NUMBER() OVER (
      PARTITION BY b.id, b.company_use
      ORDER BY b.ts_updated DESC
    ) AS rn
  FROM
    datalake_vans_clean.boleto b
  LEFT JOIN datalake_vans_clean.boleto_file bf
    ON b.id = bf.id_boleto
  LEFT JOIN datalake_vans_clean.file f
    ON f.id = bf.id_file
  WHERE
    b.status IS NOT NULL
    AND b.requested_by = 'seubarriga'
    AND b.id_related_document IS NOT NULL
    AND b.related_document_type = 'invoice'
    AND f.type = ':file.type/boleto'
    AND DATE(b.ts_created) >= DATE('2024-01-01')
),

payments_base AS (
  SELECT
    COALESCE(cb.id_charge, wb.id_charge) AS id_charge,
    cb.id_order,
    COALESCE(cb.id_business_entity, wb.id_business_entity) AS id_business_entity,
    COALESCE(cb.id_finance_entity, wb.id_finance_entity) AS id_finance_entity,
    COALESCE(cb.id_requester, CAST(wb.id_store AS VARCHAR(10))) AS id_requester,
    wb.id_chargeback,
    COALESCE(cb.payment_status, wb.charge_status) AS payment_status,
    COALESCE(cb.payment_method, wb.payment_method) AS payment_method,
    COALESCE(cb.system_origin, wb.requester_name) AS system_origin,
    COALESCE(cb.due_amount, wb.amount) AS due_amount,
    cb.paid_amount,
    COALESCE(cb.refund_amount, wb.refund_amount) AS refund_amount,
    wb.chargeback_amount,
    cb.convenience_fee_amount,
    COALESCE(cb.acquire_fee_amount, wb.acquire_fee_amount) AS acquire_fee_amount,
    cb.installment_fee_amount,
    COALESCE(cb.installments, wb.installments) AS installments,
    COALESCE(cb.card_brand, wb.card_brand) AS card_brand,
    CASE
      WHEN COALESCE(cb.payment_method, wb.payment_method) = 'CREDIT_CARD' THEN wb.acquire_error_type
      ELSE cb.error_type
    END AS error_type,
    wb.acquire_message,
    wb.chargeback_reason,
    cb.method_created_to_paid_latency_seconds,
    DATE(COALESCE(cb.ts_method_created, wb.ts_updated)) AS dt_method_created,
    COALESCE(cb.dt_due, DATE(wb.ts_due), wb.ts_updated) AS dt_due,
    COALESCE(cb.dt_business_due, wb.dt_business_due, wb.ts_updated) AS dt_business_due,
    DATE(COALESCE(cb.ts_charge_paid, wb.ts_paid)) AS dt_charge_paid,
    DATE(cb.ts_charge_canceled) AS dt_canceled,
    wb.dt_chargeback_requested,
    wb.dt_chargeback_processed,
    COALESCE(cb.datasource, wb.datasource) AS datasource
  FROM
    (SELECT * FROM checkout_base WHERE rn = 1) cb
  FULL OUTER JOIN
    (SELECT * FROM wallstreet_base WHERE rn = 1) wb
    ON cb.id_finance_entity = wb.id_finance_entity
    AND cb.code = CAST(wb.code AS VARCHAR(30))
),

payments_base_final AS (
  SELECT *, date_diff('day', dt_business_due, dt_charge_paid) AS diff_days
  FROM payments_base

  UNION ALL

  SELECT
    id_charge, id_order, id_business_entity, id_finance_entity,
    id_requester, id_chargeback, payment_status, payment_method,
    system_origin, due_amount, paid_amount, refund_amount,
    chargeback_amount, convenience_fee_amount, acquire_fee_amount,
    installment_fee_amount, installments, card_brand, error_type,
    acquire_message, chargeback_reason,
    method_created_to_paid_latency_seconds, dt_method_created,
    dt_due, dt_business_due, dt_charge_paid, dt_canceled,
    dt_chargeback_requested, dt_chargeback_processed, datasource,
    date_diff('day', dt_business_due, dt_charge_paid) AS diff_days
  FROM vans_base
  WHERE rn = 1
)

SELECT
  id_charge,
  id_order,
  id_business_entity,
  id_finance_entity,
  id_requester,
  id_chargeback,
  payment_status AS original_status,
  CASE
    WHEN payment_status = 'CAPTURED' THEN 'PAID'
    WHEN payment_status IN ('PENDING_REGISTER_PAYMENT', 'PROCESSING_REFUND',
      'PENDING_CAPTURE', 'PENDING_CANCELATION') THEN 'PROCESSING'
    WHEN payment_status IN ('WRITTEN_DOWN_ERROR', 'WRITE_DOWN_PAID_REQUESTED',
      'WRITE_DOWN_REQUESTED') THEN 'WRITTEN_DOWN'
    WHEN payment_status IN ('REQUESTED', 'CREATED', 'CHANGED') THEN 'OPEN'
    WHEN payment_status IN ('CHARGEBACK_CAPTURED') THEN 'CHARGEBACK'
    WHEN payment_status IN ('CAPTURE_DENIED', 'CAPTURE_BLOCKED',
      'CAPTURE_NOT_PROCESSED', 'CANCELATION_NOT_PROCESSED') THEN 'ERROR'
    ELSE payment_status
  END AS payment_status,
  payment_method,
  system_origin,
  CASE
    WHEN system_origin IN ('seubarriga', 'seubarriga-checkout',
      'rent-invoice-payment', 'rental-recurrent-creditcard-payment') THEN 'Rental'
    WHEN system_origin IN ('rental-offer', 'rental-offer-checkout') THEN 'Rental Offer'
    WHEN system_origin IN ('pro-guarantor-checkout', 'pro-guarantor',
      'rental-guarantee') THEN 'Rental Guarantee'
    WHEN system_origin IN ('trato-feito', 'trato-feito-cyber',
      'trato-feito-5a-collector', 'collections', 'seumadruga') THEN 'Collections'
    WHEN system_origin = 'reservation' THEN 'Reservation'
    WHEN system_origin = 'rental-guarantee-platform' THEN 'Quintocred'
    ELSE system_origin
  END AS product_origin,
  IF(system_origin = 'rental-recurrent-creditcard-payment',
    'recurrent', 'one time') AS is_recurrent,
  due_amount,
  paid_amount,
  refund_amount,
  chargeback_amount,
  convenience_fee_amount,
  acquire_fee_amount,
  installment_fee_amount,
  CAST(convenience_fee_amount + installment_fee_amount
    - acquire_fee_amount AS DECIMAL(20, 4)) AS total_cc_fee_amount,
  installments,
  CASE
    WHEN card_brand NOT IN ('Mastercard', 'Visa', 'Elo') THEN 'Outros'
    ELSE card_brand
  END AS card_brand,
  error_type,
  acquire_message,
  chargeback_reason,
  method_created_to_paid_latency_seconds,
  dt_method_created,
  dt_due,
  dt_business_due,
  dt_charge_paid,
  dt_canceled,
  dt_chargeback_requested,
  dt_chargeback_processed,
  datasource,
  diff_days,
  CASE
    WHEN diff_days <= 0 THEN 'paid until due date'
    WHEN diff_days > 0 THEN 'paid late'
    WHEN dt_charge_paid IS NULL THEN 'not paid'
    ELSE NULL
  END AS payment_date_status,
  CASE
    WHEN diff_days <= -8 THEN 'A - 8d or More Early'
    WHEN diff_days BETWEEN -7 AND -3 THEN 'B - 3d to 7d Early'
    WHEN diff_days = -2 THEN 'C - 2d Early'
    WHEN diff_days = -1 THEN 'D - 1d Early'
    WHEN diff_days = 0 THEN 'E - 0d On Time'
    WHEN diff_days >= 1 THEN 'F - 1d or More Late'
    WHEN dt_charge_paid IS NULL THEN NULL
  END AS payment_segmentation
FROM payments_base_final
WHERE id_requester NOT IN ('4', '10')
```

**Notes:**
- Checkout ↔ Wall Street are joined via `FULL OUTER JOIN` on `(id_finance_entity, code)` — this merges the same transaction seen by both systems.
- Vans is `UNION ALL`'d separately (no overlap with Checkout/Wall Street on the join keys).
- Wall Street amounts are stored in **cents** — divide by 100 (`CAST(amount AS DECIMAL(10,2)) / 100`).
- The `payment_segmentation` column produces ordered buckets (A through F) for easy sorting in dashboards.
- Filter `id_requester NOT IN ('4', '10')` to exclude internal/test requesters.
