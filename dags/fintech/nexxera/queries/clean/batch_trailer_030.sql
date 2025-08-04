-- IN THIS TABLE WE HAVE VERSION 030 FOR BOTH ITAÚ AND BRADESCO
SELECT
    id_bank,
    id_service_batch,
    record_type,
    file_name,
    SUBSTRING(metadata, 10, 1) AS company_register_type,
    SUBSTRING(metadata, 11, 14) AS company_register_number,
    CAST(SUBSTRING(metadata, 25, 20) AS INTEGER) AS bank_insurance_code,
    CAST(SUBSTRING(metadata, 45, 5) AS INTEGER) AS company_agency_number,
    SUBSTRING(metadata, 50, 1) AS company_agency_digit,
    CAST(SUBSTRING(metadata, 51, 12) AS INTEGER) AS company_account_number,
    SUBSTRING(metadata, 63, 1) AS company_account_digit,
    SUBSTRING(metadata, 64, 1) AS agency_account_digit,
    SUBSTRING(metadata,65,30) AS company_name,
    CAST(SUBSTRING(metadata, 99, 18)/ 100 AS DECIMAL(16,2)) AS account_limit,
    CAST(SUBSTRING(metadata, 117, 18)/ 100 AS DECIMAL(16,2)) AS blocked_balance,
    CAST(SUBSTRING(metadata, 143, 18)/ 100 AS DECIMAL(16,2)) AS final_balance_value,
    SUBSTRING(metadata, 161, 1) AS final_balance_situation,
    SUBSTRING(metadata, 162, 1) AS final_balance_position,
    CAST(SUBSTRING(metadata, 163, 6) AS INTEGER) AS batch_registers_amount,
    CAST(SUBSTRING(metadata, 169, 18)/ 100 AS DECIMAL(16,2)) AS debit_value,
    CAST(SUBSTRING(metadata, 187, 18)/ 100 AS DECIMAL(16,2)) AS credit_value,
    SUBSTRING(metadata, 205, 28) AS cnab_reserved_field,
    TO_DATE(SUBSTRING(metadata, 135, 8), 'ddMMyyyy') AS dt_final_balance,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial_extracts
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND id_bank IN (341, 237)
    AND record_type = 5
    AND SUBSTRING(file_name, 48, 14) = 'ext_237_93738_'
