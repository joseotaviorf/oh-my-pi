SELECT
    i.id,
    i.external_id AS id_invoice,
    i.original_invoice_external_id AS id_original_invoice_external,
    i.account_id AS id_account,
    c.id_external AS id_contract,
    i.contract_id AS id_contract_internal,
    i.checkout_order_id AS id_checkout_order,
    i.checkout_charge_id AS id_checkout_charge,
    i.idempotency_id AS id_idempotency,
    CASE
      WHEN i.op_cdc = 'c' THEN "CREATE"
      WHEN i.op_cdc = 'r' THEN "READ"
      WHEN i.op_cdc = 'u' THEN "UPDATE"
      WHEN i.op_cdc = 'd' THEN "DELETE"
    END AS log_type,
    REPLACE(ai.type, '-', ' ') AS user,
    i.cdc_binlog_position,
    i.status,
    i.sub_status AS substatus,
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
    i.write_off AS is_write_off,
    i.accrual_year_month_count,
    IF(dd.is_brz_fintech_business_day, DATE(TIMESTAMP(i.due_date)), dd.next_brz_fintech_business_day) AS dt_due_adjusted,
    i.write_off_at AS ts_write_off,
    TIMESTAMP(i.paid_date) AS ts_paid,
    TIMESTAMP(i.payment_confirmation_at) AS ts_payment_confirmation,
    TIMESTAMP(i.payment_event_at) AS ts_payment_event,
    TIMESTAMP(i.payment_divergent_fixed_at) AS ts_payment_divergent_fixed,
    TIMESTAMP(i.payment_processing_at) AS ts_payment_processing,
    TIMESTAMP(i.payment_credit_date) AS ts_payment_credit,
    TIMESTAMP(i.payment_chargeback_at) AS ts_payment_chargeback,
    TIMESTAMP(i.payment_refunded_at) AS ts_payment_refunded,
    TIMESTAMP(i.canceled_at) AS ts_canceled,
    TIMESTAMP(i.sent_at) AS ts_sent,
    TIMESTAMP(i.due_date) AS ts_due,
    TIMESTAMP(i.created_at) AS ts_created,
    TIMESTAMP(i.synced_at) AS ts_synced,
    TIMESTAMP(i.nf_requested_at) as ts_nf_requested,
    TIMESTAMP(i.retsuko_created_at) AS ts_retsuko_created,
    TIMESTAMP(i.retsuko_updated_at) AS ts_retsuko_updated,
    TIMESTAMP(i.ts_cdc_transaction) AS ts_cdc_transaction,
    TIMESTAMP(i.ts_database_transaction) AS ts_database_transaction,
    i.year,
    i.month,
    i.day,
    NOW() AS ts_load
FROM
    datalake_retsuko_transactional.invoice AS i
LEFT JOIN
  datalake_retsuko_clean.contract AS c
    ON c.id = i.contract_id
LEFT JOIN
  datalake_retsuko_clean.account AS ai
    ON i.account_id = ai.id
LEFT JOIN datalake_quintoandar.aux_date AS dd
    ON dd.date = DATE(TIMESTAMP(i.due_date))
WHERE MAKE_DATE(i.year, i.month, i.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
