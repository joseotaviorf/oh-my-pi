SELECT
    id,
    external_id AS id_external,
    invoice_id AS id_invoice,
    contract_id AS id_contract,
    audit_id AS id_audit,
    from_account_id AS id_from_account,
    to_account_id AS id_to_account,
    reversed_entry_external_id AS id_external_reversed_entry,
    amount,
    bill_item,
    description,
    producer,
    accrual_year_month,
    due_year_month,
    timestamp(created_at) AS ts_created,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated,
    year,
    month,
    day
FROM
    datalake_homolog_retsuko_raw.entry
WHERE
    (
        year = {year}
        AND month = {month}
        AND day = {day} - 1
    )
    OR
    (
        year = {year}
        AND month = {month}
        AND day = {day}
    )
