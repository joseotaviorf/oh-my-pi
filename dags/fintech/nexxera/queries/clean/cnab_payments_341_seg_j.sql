SELECT 
    id_bank,
    SUBSTRING(metadata, 4, 3) AS id_destination_bank,
    id_service_batch,
    SUBSTRING(metadata, 7, 1) AS id_currency,
    substring_index(substring_index(file_name, '_', -3), '_', 1) AS bank_account,
    record_type,
    record_sequence_number,
    segment_type,
    SUBSTRING(metadata, 1, 3) AS transaction_type,
    SUBSTRING(metadata, 8, 1) AS barcode_verification_digit,
    SUBSTRING(metadata, 9, 4) AS barcode_maturity_factor,
    TRIM(SUBSTRING(metadata, 48, 30)) AS beneficiarys_name,
    SUBSTRING(metadata, 23, 25) AS barcode_free_field,
    SUBSTRING(metadata, 154, 15) AS record_addon,
    TRIM(REPLACE(SUBSTRING(metadata, 169, 20), '!', '|')) AS company_use,
    TRIM(SUBSTRING(metadata, 202, 15)) AS our_number,
    TRIM(SUBSTRING(metadata, 217, 10)) AS occurrence_code,
    SUBSTRING_INDEX(file_name, '/', -1) AS file_name,
    CAST(SUBSTRING(metadata, 86, 15)/100 AS DECIMAL(32,2)) AS due_amount,
    CAST(SUBSTRING(metadata, 101, 15)/100 AS DECIMAL(32,2)) AS discount_amount,
    CAST(SUBSTRING(metadata, 116, 15)/100 AS DECIMAL(32,2)) AS fine_amount,
    CAST(SUBSTRING(metadata, 139, 15)/100 AS DECIMAL(32,2)) AS paid_amount,
    CAST(SUBSTRING(metadata, 13, 10)/100 AS DECIMAL(32,2)) AS barcode_amount,
    TO_DATE(SUBSTRING(metadata, 78, 8), 'ddMMyyyy') AS dt_due,
    TO_DATE(SUBSTRING(metadata, 131, 8), 'ddMMyyyy') AS dt_paid,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM 
    datalake_nexxera_raw.cnab_payments
WHERE 
    segment_type = 'J'
AND
    id_bank = '341'
AND
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'