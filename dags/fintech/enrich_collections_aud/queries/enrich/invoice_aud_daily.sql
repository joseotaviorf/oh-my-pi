WITH
invoice_range AS (
    SELECT
        id_invoice,
        DATE(MIN(ts_database_transaction)) AS dt_first_transaction,
        DATE(COALESCE(
                MAX(CASE WHEN ts_paid IS NOT NULL
                    OR ts_canceled IS NOT NULL THEN ts_database_transaction END),
                CURRENT_DATE
        )) AS dt_last_transaction
    FROM datalake_collections_aud.invoice_aud
    GROUP BY 1
),
daily_changes AS (
    SELECT
        id,
        id_invoice,
        id_original_invoice_external,
        id_account,
        id_contract,
        id_contract_internal,
        id_checkout_order,
        id_checkout_charge,
        id_idempotency,
        user,
        cdc_binlog_position,
        status,
        substatus,
        payment_status,
        paid_via,
        purpose,
        closing_mode,
        reason,
        due_amount,
        paid_amount,
        payment_paid_interest_amount,
        payment_paid_fine_amount,
        accrual_year_month,
        should_request_boleto,
        sispag_file,
        payment_company_use_number,
        payment_bank_code,
        payment_style_mapped,
        is_write_off,
        accrual_year_month_count,
        dt_due_adjusted,
        ts_write_off,
        ts_paid,
        ts_payment_confirmation,
        ts_payment_event,
        ts_payment_divergent_fixed,
        ts_payment_processing,
        ts_payment_credit,
        ts_payment_chargeback,
        ts_payment_refunded,
        ts_canceled,
        ts_sent,
        ts_due,
        ts_created,
        ts_synced,
        ts_nf_requested,
        ts_retsuko_created,
        ts_retsuko_updated,
        ts_cdc_transaction,
        ts_database_transaction,
        year,
        month,
        day,
        DATE(ts_database_transaction) AS dt_reference
    FROM datalake_collections_aud.invoice_aud
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice, DATE(ts_database_transaction) ORDER BY ts_database_transaction DESC) = 1
),
get_next_day AS (
    SELECT *,
        COALESCE(
        LEAD(dt_reference) OVER(PARTITION BY id_invoice ORDER BY dt_reference),
        CURRENT_DATE + INTERVAL 1 DAY) AS dt_next_day
    FROM daily_changes
),
invoice_days AS (
    SELECT
        id_invoice,
        dt_reference
    FROM invoice_range
    LATERAL VIEW EXPLODE(
        SEQUENCE(dt_first_transaction,
                dt_last_transaction,
                INTERVAL 1 DAY
            )) AS dt_reference
)
SELECT
    dc.id,
    dc.id_invoice,
    id.dt_reference,
    dc.id_original_invoice_external,
    dc.id_account,
    dc.id_contract,
    dc.id_contract_internal,
    dc.id_checkout_order,
    dc.id_checkout_charge,
    dc.id_idempotency,
    dc.user,
    dc.cdc_binlog_position,
    dc.status,
    dc.substatus,
    dc.payment_status,
    dc.paid_via,
    dc.purpose,
    dc.closing_mode,
    dc.reason,
    dc.due_amount,
    dc.paid_amount,
    dc.payment_paid_interest_amount,
    dc.payment_paid_fine_amount,
    dc.accrual_year_month,
    dc.should_request_boleto,
    dc.sispag_file,
    dc.payment_company_use_number,
    dc.payment_bank_code,
    dc.payment_style_mapped,
    dc.is_write_off,
    dc.accrual_year_month_count,
    dc.dt_due_adjusted,
    dc.ts_write_off,
    dc.ts_paid,
    dc.ts_payment_confirmation,
    dc.ts_payment_event,
    dc.ts_payment_divergent_fixed,
    dc.ts_payment_processing,
    dc.ts_payment_credit,
    dc.ts_payment_chargeback,
    dc.ts_payment_refunded,
    dc.ts_canceled,
    dc.ts_sent,
    dc.ts_due,
    dc.ts_created,
    dc.ts_synced,
    dc.ts_nf_requested,
    dc.ts_retsuko_created,
    dc.ts_retsuko_updated,
    dc.ts_cdc_transaction,
    dc.ts_database_transaction,
    dc.ts_cdc_transaction AS ts_snapshot,
    YEAR(id.dt_reference) AS year,
    MONTH(id.dt_reference) AS month,
    DAY(id.dt_reference) AS day,
    NOW() AS ts_load
FROM invoice_days AS id
CROSS JOIN get_next_day AS dc
         ON dc.id_invoice = id.id_invoice
         AND id.dt_reference >= dc.dt_reference
         AND id.dt_reference < dc.dt_next_day
