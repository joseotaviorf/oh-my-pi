-- IN THIS TABLE WE HAVE VERSIONS 050 AND 030 FOR BOTH ITAÚ AND BRADESCO
SELECT
    id_bank,
    id_service_batch,
    record_type,
    SUBSTRING(metadata, 1, 1) AS operation_type,
    SUBSTRING(metadata, 2, 2) AS service_type,
    SUBSTRING(metadata, 4, 2) AS launch_type,
    SUBSTRING(metadata, 6, 3) AS file_layout_version,
    SUBSTRING(metadata, 10, 1) AS company_register_type,
    SUBSTRING(metadata, 11, 14) AS company_register_number,
    SUBSTRING(metadata, 25, 4) AS account_type,
    CAST(SUBSTRING(metadata, 29, 16) AS INTEGER) AS bank_insurance_code,
    CAST(SUBSTRING(metadata, 45, 5) AS INTEGER) AS company_agency_number,
    SUBSTRING(metadata, 50, 1) AS company_agency_digit,
    CAST(SUBSTRING(metadata, 51, 12) AS INTEGER) AS company_account_number,
    SUBSTRING(metadata, 63, 1) AS company_account_digit,
    SUBSTRING(metadata, 64, 1) AS agency_account_digit,
    SUBSTRING(metadata, 65, 30) AS company_name,
    SUBSTRING(metadata, 95, 40) AS second_line_extract,
    CAST(SUBSTRING(metadata, 143, 18)/ 100 AS DECIMAL(16,2)) AS inicial_balance_value,
    SUBSTRING(metadata, 161, 1) AS inicial_balance_situation,
    SUBSTRING(metadata, 162, 1) AS inicial_balance_position,
    SUBSTRING(metadata, 163, 3) AS extract_currency,
    CAST(SUBSTRING(metadata, 166, 5) AS INTEGER) AS extract_sequence_number,
    SUBSTRING(metadata, 171, 62) AS cnab_reserved_field,
    TO_DATE(SUBSTRING(metadata, 135, 8), 'ddMMyyyy') AS dt_inicial_balance,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial_extracts
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND id_bank IN (341, 237)
    AND record_type = 1
    AND SUBSTRING(metadata, 6, 3) NOT IN ('080', '081')
