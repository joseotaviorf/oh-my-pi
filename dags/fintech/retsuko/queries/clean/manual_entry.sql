SELECT
  id,
  contract_id AS id_contract,
  from_account AS id_from_account,
  to_account AS id_to_account,
  external_id AS id_external,
  from_entry AS id_from_entry,
  to_entry AS id_to_entry,
  audit AS id_audit,
  producer,
  type,
  description,
  amount,
  installment_number,
  installment_total_number,
  installment_total_amount,
  is_removed,
  accrual_year_month,
  accrued_date AS dt_accrued,
  last_operation_date AS ts_last_operation
FROM
  datalake_retsuko_raw.manual_entry
