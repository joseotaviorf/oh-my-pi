SELECT 
    id_bank,
    id_service_batch,
    substring_index(substring_index(file_name, '_', -3), '_', 1) AS bank_account,
    record_type,
    record_sequence_number,
    segment_type,
    SUBSTRING(metadata, 1, 3) AS transaction_type,
    SUBSTRING(metadata, 4, 48) AS barcode,
    SUBSTRING(metadata, 52, 30) AS taxpayer_concessionaire,
    SUBSTRING(metadata, 90, 3) AS currency,
    SUBSTRING(metadata, 149, 9) AS invoice,
    TRIM(REPLACE(SUBSTRING(metadata, 161, 20), '!', '|')) AS company_use,
    TRIM(SUBSTRING(metadata, 202, 15)) AS our_number,
    TRIM(SUBSTRING(metadata, 217, 10)) AS occurrence_code,
    SUBSTRING_INDEX(file_name, '/', -1) as file_name,
    CAST(SUBSTRING(metadata, 108, 15)/100 AS DECIMAL(32,2)) AS due_amount,
    CAST(SUBSTRING(metadata, 131, 15)/100 AS DECIMAL(32,2)) AS paid_amount,
    CAST(SUBSTRING(metadata, 93, 15)/100 AS DECIMAL(32,2)) AS currency_amount,
    TO_DATE(SUBSTRING(metadata, 82, 8), 'ddMMyyyy') AS dt_due,
    TO_DATE(SUBSTRING(metadata, 123, 8), 'ddMMyyyy') AS dt_paid,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.cnab_payments
WHERE
    segment_type = 'O'
AND
    id_bank = '341'
AND
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'