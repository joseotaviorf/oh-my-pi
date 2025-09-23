WITH
first_business_day AS (
   SELECT DISTINCT
        month_start,
        date,
        CASE
            WHEN date = MIN(CASE WHEN is_brz_fintech_business_day THEN date END) OVER (PARTITION BY month_start)
            THEN TRUE
            ELSE FALSE
        END AS is_first_business_day_month,
        LEAD(date) OVER(ORDER BY date) AS dt_snapshot
    FROM datalake_quintoandar.aux_date
    WHERE DATE(date) BETWEEN '2024-04-24' AND CURRENT_DATE
),
snapshot_days AS (
  SELECT
      *,
      LAST_DAY(DATEADD(MONTH, -1, month_start)) AS dt_previous_end_month
  FROM first_business_day
  WHERE is_first_business_day_month = TRUE
),
calculate_dt_closing AS (
    SELECT
        i.id,
        i.id_invoice,
        i.id_original_invoice_external,
        i.id_contract,
        i.id_account,
        i.id_contract_internal,
        i.id_checkout_order,
        i.id_checkout_charge,
        i.id_idempotency,
        i.user,
        i.cdc_binlog_position,
        i.status,
        i.substatus,
        i.payment_status,
        i.paid_via,
        i.purpose,
        i.closing_mode,
        i.reason,
        i.due_amount,
        i.paid_amount,
        i.payment_paid_interest_amount,
        i.payment_paid_fine_amount,
        i.accrual_year_month,
        i.should_request_boleto,
        i.sispag_file,
        i.payment_company_use_number,
        i.payment_bank_code,
        i.payment_style_mapped,
        i.is_write_off,
        i.accrual_year_month_count,
        i.dt_due_adjusted,
        LAST_DAY(i.dt_reference) AS dt_month_end,
        CASE
            WHEN DATE(i.ts_database_transaction) BETWEEN sd.dt_previous_end_month AND sd.dt_snapshot
            THEN sd.dt_previous_end_month
            ELSE LAST_DAY(i.dt_reference)
        END AS dt_closing,
        sd.dt_snapshot,
        i.ts_write_off,
        i.ts_paid,
        i.ts_payment_confirmation,
        i.ts_payment_event,
        i.ts_payment_divergent_fixed,
        i.ts_payment_processing,
        i.ts_payment_credit,
        i.ts_payment_chargeback,
        i.ts_payment_refunded,
        i.ts_canceled,
        i.ts_sent,
        i.ts_due,
        i.ts_created,
        i.ts_synced,
        i.ts_nf_requested,
        i.ts_retsuko_created,
        i.ts_retsuko_updated,
        i.ts_cdc_transaction,
        i.ts_database_transaction,
        YEAR(LAST_DAY(i.dt_reference)) As year,
        MONTH(LAST_DAY(i.dt_reference)) AS month,
        DAY(LAST_DAY(i.dt_reference)) AS day,
        NOW() AS ts_load
    FROM
        datalake_collections_aud.invoice_aud_daily AS i
    LEFT JOIN
        snapshot_days AS sd
            ON DATE_TRUNC("MONTH", i.dt_reference) = sd.month_start
)
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
    dt_month_end,
    dt_closing,
    dt_snapshot,
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
    ts_load
FROM calculate_dt_closing
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice, dt_closing ORDER BY ts_database_transaction DESC) = 1
