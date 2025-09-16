WITH
invoice_range AS (
    SELECT
        id_invoice,
        DATE(DATE_TRUNC('MONTH', MIN(ts_database_transaction))) AS dt_first_transaction,
        DATE(DATE_TRUNC('MONTH', COALESCE(
                MAX(CASE WHEN ts_paid IS NOT NULL THEN ts_database_transaction END),
                CURRENT_DATE
        ))) AS dt_last_transaction
    FROM datalake_collections_aud.invoice_aud_daily
    GROUP BY 1
),
monthly_changes AS (
    SELECT
        id,
        id_invoice,
        id_original_invoice_external,
        id_contract,
        id_account,
        id_contract_internal,
        id_checkout_order,
        id_checkout_charge,
        id_idempotency,
        log_type,
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
        DATE_TRUNC('MONTH', ts_database_transaction) AS dt_month_start
    FROM datalake_collections_aud.invoice_aud_daily
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice, DATE_TRUNC('MONTH', ts_database_transaction) ORDER BY ts_database_transaction  DESC) = 1
),
get_next_month AS (
    SELECT *,
        COALESCE(
        LEAD(dt_month_start) OVER(PARTITION BY id_invoice ORDER BY dt_month_start),
        DATE_TRUNC('MONTH',CURRENT_DATE)) AS dt_next_month_start
    FROM monthly_changes
),
invoice_months AS (
    SELECT
        id_invoice,
        dt_month_start
    FROM invoice_range
    LATERAL VIEW EXPLODE(
        SEQUENCE(dt_first_transaction,
                dt_last_transaction,
                INTERVAL 1 MONTH
            )) AS dt_month_start
)
SELECT
    nm.id,
    nm.id_invoice,
    nm.id_original_invoice_external,
    nm.id_contract,
    nm.id_account,
    nm.id_contract_internal,
    nm.id_checkout_order,
    nm.id_checkout_charge,
    nm.id_idempotency,
    nm.log_type,
    nm.user,
    nm.cdc_binlog_position,
    nm.status,
    nm.substatus,
    nm.payment_status,
    nm.paid_via,
    nm.purpose,
    nm.closing_mode,
    nm.reason,
    nm.due_amount,
    nm.paid_amount,
    nm.payment_paid_interest_amount,
    nm.payment_paid_fine_amount,
    nm.accrual_year_month,
    nm.should_request_boleto,
    nm.sispag_file,
    nm.payment_company_use_number,
    nm.payment_bank_code,
    nm.payment_style_mapped,
    nm.is_write_off,
    nm.accrual_year_month_count,
    nm.dt_due_adjusted,
    LAST_DAY(im.dt_month_start) AS dt_closing,
    nm.ts_write_off,
    nm.ts_paid,
    nm.ts_payment_confirmation,
    nm.ts_payment_event,
    nm.ts_payment_divergent_fixed,
    nm.ts_payment_processing,
    nm.ts_payment_credit,
    nm.ts_payment_chargeback,
    nm.ts_payment_refunded,
    nm.ts_canceled,
    nm.ts_sent,
    nm.ts_due,
    nm.ts_created,
    nm.ts_synced,
    nm.ts_nf_requested,
    nm.ts_retsuko_created,
    nm.ts_retsuko_updated,
    nm.ts_cdc_transaction,
    nm.ts_database_transaction,
    nm.ts_cdc_transaction AS ts_snapshot,
    YEAR(im.dt_month_start) As year,
    MONTH(im.dt_month_start) AS month,
    DAY(LAST_DAY(im.dt_month_start)) AS day,
    NOW() AS ts_load
FROM invoice_months As im
CROSS JOIN get_next_month AS nm
         ON nm.id_invoice = im.id_invoice
         AND im.dt_month_start >= nm.dt_month_start
         AND im.dt_month_start < nm.dt_next_month_start
