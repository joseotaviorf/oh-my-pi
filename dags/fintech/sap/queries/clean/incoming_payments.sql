SELECT
    CAST(transaction_id_transid AS STRING) AS id_transaction,
    business_entity_id_u_businessentityid AS id_business_entity,
    financial_entity_id_u_financeentityid AS id_financial_entity,
    external_payment_id_u_externalpaymentid AS id_external_payment,
    createdby_usersign AS id_user_sign,
    legacy_uuid_u_rsd_uuidsb AS legacy_uuid,
    uuid_u_oinv_uuid AS uuid,
    docentry AS document_entry,
    -- CASE
    --     WHEN
    --         createdby_usersign IN (1, 83)
    --         AND (
    --             uuid_u_oinv_uuid IS NULL
    --             OR legacy_uuid_u_rsd_uuidsb IS NULL
    --             OR uuid_u_oinv_uuid RLIKE '^[a-z]{{1}}:.*$'
    --             OR legacy_uuid_u_rsd_uuidsb RLIKE '^[a-z]{{1}}:.*$'
    --         ) THEN REGEXP_EXTRACT(memo, '((?:CI|CR|FC|FP|CP).*)')
    --     ELSE REGEXP_EXTRACT(memo, '^"?.*(?<clean>(?:CI|CR|FC|FP|CP)[^ -]+)[ -]?.*"?$')
    -- END AS memo,
    memo,
    number_number AS source_document_number,
    series_series AS series,
    source_client_u_sourceclient AS source_client,
    transaction_type_transtype AS transaction_type,
    updatedby_usersign2 AS updated_by,
    accrualdate_u_accrualdate AS accrual_year_month,
    loctotal AS loc_total,
    TO_DATE(docdate, 'yyyyMMdd') AS dt_document,
    TO_DATE(taxdate, 'yyyyMMdd') AS dt_tax,
    TO_DATE(refdate, 'yyyyMMdd') AS dt_reference,
    TO_DATE(duedate, 'yyyyMMdd') AS dt_due,
    TO_DATE(createdate, 'yyyyMMdd') AS dt_created,
    TO_DATE(updatedate, 'yyyyMMdd') AS dt_updated,
    year,
    month,
    day
FROM
    datalake_pas_raw.incoming_payments
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
