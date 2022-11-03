SELECT
    CAST(transaction_id_transid AS STRING) AS id_transaction,
    business_entity_id_numatcard AS id_business_entity,
    external_payment_id_u_externalpaymentid AS id_external_payment,
    financial_entity_id_u_financeentityid AS id_financial_entity,
    createdby_usersign AS id_user_sign,
    uuid_u_rsd_uuid AS uuid,
    legacy_uuid_u_rsd_uuidsb AS legacy_uuid,
    document AS id_document,
    docentry AS document_entry,
    memo,
    number_number AS source_document_number,
    series_series AS series,
    source_client_u_sourceclient AS source_client,
    transaction_type_transtype AS transaction_type,
    updatedby_usersign2 AS updated_by,
    loctotal AS loc_total,
    TO_DATE(docdate, 'yyyyMMdd') AS dt_document,
    TO_DATE(accrualdate_u_accrualdate, 'yyyyMMdd') AS dt_accrual,
    TO_DATE(taxdate, 'yyyyMMdd') AS dt_tax,
    TO_DATE(refdate, 'yyyyMMdd') AS dt_reference,
    TO_DATE(duedate, 'yyyyMMdd') AS dt_due,
    TO_DATE(createdate, 'yyyyMMdd') AS dt_created,
    TO_DATE(updatedate, 'yyyyMMdd') AS dt_updated,
    year,
    month,
    day
FROM
    datalake_pas_raw.invoices
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
