SELECT
    id,
    external_id as id_external,
    invoice_id as id_invoice,
    identifier,
    due_amount,
    our_number,
    our_number_digit,
    wallet_number,
    barcode,
    inputtable_line,
    timestamp(due_date) as ts_due,
    timestamp(issue_date) as ts_issued,
    timestamp(created_at) as ts_created,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated,
    year,
    month,
    day
FROM
    datalake_homolog_retsuko_raw.boleto
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
