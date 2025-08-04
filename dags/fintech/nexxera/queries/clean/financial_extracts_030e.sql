-- IN THIS TABLE WE HAVE VERSION 030 FOR BOTH ITAÚ AND BRADESCO
SELECT
    id_bank,
    id_service_batch,
    record_type,
    SUBSTRING(metadata, 1, 5) AS sequencial_batch_register,
    SUBSTRING(metadata, 6, 1) AS segment_code,
    SUBSTRING(metadata, 9, 1) AS company_register_type,
    SUBSTRING(metadata, 11, 14) AS company_register_number,
    CAST(SUBSTRING(metadata, 25, 20) AS INTEGER) AS bank_insurance_code,
    CAST(SUBSTRING(metadata, 45, 5) AS INTEGER) AS company_agency_number,
    SUBSTRING(metadata, 50, 1) AS company_agency_digit,
    CAST(SUBSTRING(metadata, 51, 12) AS INTEGER) AS company_account_number,
    SUBSTRING(metadata, 63, 1) AS company_account_digit,
    SUBSTRING(metadata, 64, 1) AS agency_account_digit,
    SUBSTRING(metadata, 65, 30) AS company_name,
    SUBSTRING(metadata, 95, 40) AS cnab_reserved_field,
    CAST(SUBSTRING(metadata, 143, 18)/ 100 AS DECIMAL(16,2)) AS launch_value,
    SUBSTRING(metadata, 161, 1) AS launch_type,
    SUBSTRING(metadata, 162, 3) AS launch_category,
    SUBSTRING(metadata, 165, 4) AS bank_code,
    SUBSTRING(metadata, 169, 25) AS history_description,
    SUBSTRING(metadata, 194, 20) AS document_number,
    file_name,
    TO_DATE(SUBSTRING(metadata, 135, 8), 'ddMMyyyy') AS dt_launch,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial_extracts
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND id_bank IN (341, 237)
    AND record_type = 3
    AND SUBSTRING(metadata, 6, 1) = 'E'
    AND SUBSTRING(file_name, 48, 14) = 'ext_237_93738_'
