WITH latest_audit AS (
  SELECT
    id_invoice,
    id_audit
  FROM
    datalake_retsuko.entry
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_invoice ORDER BY ts_database_transaction DESC) = 1
)
SELECT
    inv.id,
    inv.id_external,
    inv.id_original_invoice_external,
    inv.id_account,
    inv.id_contract,
    c.id_external AS id_contract_external,
    la.id_audit,
    inv.id_checkout_order,
    inv.id_checkout_charge,
    inv.id_idempotency,
    inv.id_external_negotiation,
    inv.payment_unique_payment_identifier,
    inv.status,
    inv.payment_status,
    inv.substatus,
    inv.negotiation_status,
    inv.paid_via,
    inv.purpose,
    inv.closing_mode,
    inv.reason,
    c.country_code,
    inv.due_amount,
    inv.paid_amount,
    inv.payment_paid_interest_amount,
    inv.payment_paid_fine_amount,
    inv.accrual_year_month,
    inv.should_request_boleto,
    inv.sispag_file,
    inv.payment_company_use_number,
    inv.payment_bank_code,
    inv.is_write_off,
    IF(dd.is_brz_fintech_business_day, DATE(inv.ts_due), dd.next_brz_fintech_business_day) AS dt_due_adjusted,
    inv.ts_write_off,
    inv.ts_paid,
    inv.ts_payment_confirmation,
    inv.ts_payment_event,
    inv.ts_payment_divergent_fixed,
    inv.ts_payment_processing,
    inv.ts_payment_credit,
    inv.ts_payment_chargeback,
    inv.ts_payment_refunded,
    inv.ts_canceled,
    inv.ts_sent,
    inv.ts_due,
    inv.ts_nf_requested,
    inv.ts_created,
    inv.ts_synced,
    inv.ts_retsuko_updated
FROM
    datalake_retsuko_clean.invoice AS inv
LEFT JOIN
  latest_audit AS la
    ON inv.id = la.id_invoice
LEFT JOIN
  datalake_retsuko_clean.contract AS c
      ON c.id = inv.id_contract
LEFT JOIN datalake_quintoandar.aux_date AS dd
  ON dd.date = DATE(inv.ts_due)
