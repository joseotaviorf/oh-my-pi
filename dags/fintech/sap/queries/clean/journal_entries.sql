SELECT
    transaction_id_transid AS id_transaction,
    business_entity_id_ref1 AS id_business_entity,
    external_payment_id_u_externalpaymentid AS id_external_payment,
    financial_entity_id_ref2 AS id_financial_entity,
    createdby_usersign AS id_user_sign,
    legacy_uuid_u_rsd_uuidsb AS legacy_uuid_rsd,
    uuid_u_rsd_uuid AS uuid_rsd,
    transaction_type_transtype AS transaction_type,
    CASE
        WHEN
            createdby_usersign IN (1, 83)
            AND (
                uuid_u_rsd_uuid IS NULL
                OR legacy_uuid_u_rsd_uuidsb IS NULL
                OR uuid_u_rsd_uuid RLIKE '^[a-z]{{1}}:.*$'
                OR legacy_uuid_u_rsd_uuidsb RLIKE '^[a-z]{{1}}:.*$'
            ) THEN REGEXP_EXTRACT(memo, '((?:CI|CR|FC|FP|CP|FQ).*)')
        ELSE REGEXP_EXTRACT(memo, '^"?.*(?<clean>(?:CI|CR|FC|FP|CP)[^ -]+)[ -]?.*"?$')
    END AS memo,
    number_number AS source_document_number,
    series_series AS series,
    source_client_u_sourceclient AS source_client,
    CAST(updatedby_usersign2 AS INT) AS updated_by,
    loctotal AS total_loc,
    TO_DATE(refdate, 'yyyyMMdd') AS dt_reference,
    TO_DATE(taxdate, 'yyyyMMdd') AS dt_tax,
    TO_DATE(accrualdate_ref3, 'yyyyMMdd') AS dt_accrual,
    TO_DATE(duedate, 'yyyyMMdd') AS dt_due,
    TO_DATE(updatedate, 'yyyyMMdd') AS dt_updated,
    TO_DATE(createdate, 'yyyyMMdd') AS dt_created,
    year,
    month,
    day
FROM
    datalake_pas_raw.journal_entries
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
