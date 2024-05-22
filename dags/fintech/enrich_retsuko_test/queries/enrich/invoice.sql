WITH latest_audit AS (
  SELECT
    id_invoice,
    id_audit,
    MAX(ts_retsuko_updated)
  FROM
    datalake_retsuko_test.entry
  GROUP BY
    id_invoice,
    id_audit
)
SELECT
    in.id,
    in.id_external,
    in.id_original_invoice_external,
    in.id_account,
    in.id_contract,
    c.id_external AS id_contract_external,
    la.id_audit,
    in.id_checkout_order,
    in.id_checkout_charge,
    in.status,
    in.payment_status,
    in.substatus,
    in.negotiation_status,
    in.paid_via,
    in.purpose,
    in.closing_mode,
    in.reason,
    c.country_code,
    in.due_amount,
    in.paid_amount,
    in.payment_paid_interest_amount,
    in.payment_paid_fine_amount,
    in.accrual_year_month,
    in.should_request_boleto,
    in.sispag_file,
    in.payment_company_use_number,
    in.payment_bank_code,
    IF(dd.is_brz_fintech_business_day, DATE(in.ts_due), dd.next_brz_fintech_business_day) AS dt_due_adjusted,
    in.ts_paid,
    in.ts_payment_confirmation,
    in.ts_payment_event,
    in.ts_payment_divergent_fixed,
    in.ts_payment_processing,
    in.ts_payment_credit,
    in.ts_canceled,
    in.ts_sent,
    in.ts_due,
    in.ts_nf_requested,
    in.ts_created,
    in.ts_synced,
    in.ts_retsuko_updated
FROM
    datalake_retsuko_test_clean.invoice AS in
LEFT JOIN
  latest_audit AS la
ON in.id = la.id_invoice
LEFT JOIN
  datalake_retsuko_test_clean.contract AS c
      ON c.id = in.id_contract
LEFT JOIN datalake_quintoandar.aux_date AS dd
  ON dd.date = DATE(in.ts_due)
