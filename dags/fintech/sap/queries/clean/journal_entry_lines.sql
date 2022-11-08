WITH cte_manual_insert AS (
    SELECT
        CAST(transaction_id_transid AS STRING) AS id_transaction,
        CASE
            WHEN
                createdby_usersign IN (1, 83)
                AND (
                    uuid_u_rsd_uuid IS NULL
                    OR legacy_uuid_u_rsd_uuidsb IS NULL
                    OR uuid_u_rsd_uuid RLIKE '^[a-z]{{1}}:.*$'
                    OR legacy_uuid_u_rsd_uuidsb RLIKE '^[a-z]{{1}}:.*$'
                ) THEN TRUE
            ELSE FALSE
        END AS manual_insert
    FROM
        datalake_pas_raw.journal_entries
)
SELECT
    transaction_id_transid AS id_transaction,
    line_id_line_id AS id_line,
    business_entity_id_ref1 AS id_business_entity,
    finance_entity_entry_id_u_financeentityentryid AS id_finance_entity_entry,
    finance_entity_id_ref2 AS id_finance_entity,
    cost_center_ocrcode2 AS cost_center_code,
    contraact_contraact AS contra_act,
    location_profitcode AS location_profit_code,
    managerial_ocrcode3 AS managerial_code,
    CASE
        WHEN cte.manual_insert = TRUE THEN REGEXP_EXTRACT(memo_linememo, '((?:CI|CR|FC|FP|CP)[^ ]+)')
        ELSE REGEXP_EXTRACT(memo_linememo, '^"?.*(?<clean>(?:CI|CR|FC|FP|CP)[^ -]+)[ -]?.*"?$')
    END AS memo_line,
    number_number AS source_document_number,
    series_series AS series,
    account_account AS account,
    account_shortname AS account_shortname,
    transaction_type_transtype AS transaction_type,
    credit,
    debit,
    TO_DATE(accrualdate_ref3line, 'yyyyMMdd') AS dt_accrual,
    TO_DATE(duedate, 'yyyyMMdd') AS dt_due,
    TO_DATE(refdate, 'yyyyMMdd') AS dt_reference,
    TO_DATE(taxdate, 'yyyyMMdd') AS dt_tax,
    year,
    month,
    day
FROM
    datalake_pas_raw.journal_entry_lines AS main_table
LEFT JOIN
    cte_manual_insert AS cte
    ON cte.id_transaction = main_table.transaction_id_transid
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
