SELECT
  transaction_id_transid AS id_transaction,
  business_entity_id_ref1 AS id_business_entity,
  financial_entity_id_ref2 AS id_financial_entity,
  financial_entity_entry_id_u_financialentityentryid AS id_financial_entity_entry,
  external_payment_id_u_externalpaymentid AS id_external_payment,
  createdby_usersign AS id_user_sign,
  uuid_u_rsd_uuid AS uuid,
  docentry AS document_entry,
  memo,
  source_client_u_sourceclient AS source_client,
  transaction_type_transtype AS transaction_type,
  updatedby_usersign2 AS updated_by,
  loctotal AS loc_total,
  docdate AS dt_document,
  accrualdate_u_accrualdate AS dt_accrual,
  taxdate AS dt_tax,
  refdate AS dt_reference,
  duedate AS dt_due,
  createdate AS dt_created,
  updatedate AS dt_updated,
  year,
  month,
  day
FROM
  datalake_sap_raw.incoming_payments
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
