SELECT
    id,
    external_id as id_external,
    invoice_id as id_invoice,
    checkout_boleto_id AS id_checkout_boleto,
    identifier,
    due_amount,
    our_number,
    our_number_digit,
    wallet_number,
    barcode,
    inputtable_line,
    external_source,
    timestamp(due_date) as ts_due,
    timestamp(issue_date) as ts_issued,
    timestamp(created_at) as ts_created,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated,
    year,
    month,
    day
FROM
    datalake_retsuko_homolog_raw.boleto
WHERE MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
