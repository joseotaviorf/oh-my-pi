SELECT 
    id_bank,
    SUBSTRING(metadata, 7, 3) AS id_destination_bank,
    id_service_batch,
    SUBSTRING(metadata, 4, 3) AS id_compensation_code,
    substring_index(substring_index(file_name, '_', -3), '_', 1) AS bank_account,
    record_type,
    record_sequence_number,
    segment_type,
    SUBSTRING(metadata, 1, 3) AS transaction_type,
    SUBSTRING(metadata, 10, 20) AS destination_bank_account,
    TRIM(SUBSTRING(metadata, 30, 30)) AS beneficiarys_name,
    TRIM(REPLACE(SUBSTRING(metadata, 60, 20), '!', '|')) AS company_use,
    SUBSTRING(metadata, 91, 8) AS ispb_code, 
    SUBSTRING(metadata, 99, 2) AS payment_account_pix,
    TRIM(SUBSTRING(metadata, 121, 15)) AS our_number,
    SUBSTRING(metadata, 164, 20) AS purpose_detail,
    TRIM(SUBSTRING(metadata, 184, 6)) AS document_number,
    TRIM(SUBSTRING(metadata, 190, 14)) AS cpf_cnpj,
    SUBSTRING(metadata, 204, 2) AS doc_purpose,
    SUBSTRING(metadata, 206, 5) AS ted_purpose,
    SUBSTRING(metadata, 216, 1) AS notice,
    TRIM(SUBSTRING(metadata, 217, 10)) AS occurrence_code,
    SUBSTRING(metadata, 88, 3) AS currency,
    SUBSTRING_INDEX(file_name, '/', -1) AS file_name,
    CAST(SUBSTRING(metadata, 106, 15)/100 AS DECIMAL(32,2)) AS due_amount,
    CAST(SUBSTRING(metadata, 149, 15)/100 AS DECIMAL(32,2)) AS paid_amount,
    TO_DATE(SUBSTRING(metadata, 80, 8), 'ddMMyyyy') AS dt_due,
    TO_DATE(SUBSTRING(metadata, 141, 8), 'ddMMyyyy') AS dt_paid,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM 
    datalake_nexxera_raw.cnab_payments
WHERE
    segment_type = 'A' 
AND
    id_bank = '341'
AND
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'