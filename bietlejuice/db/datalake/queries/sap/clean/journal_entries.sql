SELECT
  transaction_id_transid AS id_transaction,
  business_entity_id_ref1 AS id_business_entity,
  external_payment_id_u_externalpaymentid AS id_external_payment,
  financial_entity_id_ref2 AS id_financial_entity,
  createdby_usersign AS id_user_sign,
  legacy_uuid_u_rsd_uuidsb AS legacy_uuid_rsd,
  uuid_u_rsd_uuid AS uuid_rsd,
  transaction_type_transtype AS transaction_type,
  memo,
  number_number AS source_document_number,
  series_series AS series,
  source_client_u_sourceclient AS source_client,
  updatedby_usersign2 AS updated_by,
  loctotal AS total_loc,
  refdate AS dt_reference,
  taxdate AS dt_tax,
  accrualdate_ref3 AS dt_accrual,
  duedate AS dt_due,
  updatedate AS dt_updated,
  createdate AS dt_created,
  year,
  month,
  day
FROM
  datalake_sap_raw.journal_entries
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
