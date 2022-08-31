SELECT
  transaction_id_transid AS id_transaction,
  business_entity_id_u_businessentityid AS id_business_entity,
  financial_entity_id_u_financeentityid AS id_financial_entity,
  external_payment_id_u_externalpaymentid AS id_external_payment,
  createdby_usersign AS id_user_sign,
  legacy_uuid_u_rsd_uuidsb AS legacy_uuid,
  uuid_u_oinv_uuid AS uuid,
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
