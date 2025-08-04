-- IN THIS TABLE WE HAVE VERSIONS 050 AND 030 FOR BOTH ITAÚ AND BRADESCO
SELECT
    id_bank,
    id_service_batch,
    record_type,
    SUBSTRING(metadata, 10, 1) AS company_register_type,
    SUBSTRING(metadata, 11, 14) AS company_register_number,
    CAST(SUBSTRING(metadata, 25, 20) AS INTEGER) AS bank_insurance_code,
    SUBSTRING(metadata, 204, 22) AS insurance_code,
    CAST(SUBSTRING(metadata, 45, 5) AS INTEGER) AS company_agency_number,
    SUBSTRING(metadata, 50, 1) AS company_agency_digit,
    CAST(SUBSTRING(metadata, 51, 12) AS INTEGER) AS company_account_number,
    SUBSTRING(metadata, 63, 1) AS company_account_digit,
    SUBSTRING(metadata, 64, 1) AS agency_account_digit,
    SUBSTRING(metadata, 65, 30) AS company_name,
    SUBSTRING(metadata, 95, 30) AS bank_name,
    SUBSTRING(metadata, 135, 1) AS return_code,
    CAST(SUBSTRING(metadata, 150, 6) AS INTEGER) AS file_sequence_number,
    SUBSTRING(metadata, 156, 3) AS file_layout_version,
    SUBSTRING(metadata, 159, 5) AS file_record_density,
    SUBSTRING(metadata, 164, 20) AS bank_reserved_field,
    SUBSTRING(metadata, 184, 20) AS company_reserved_field,
    SUBSTRING(metadata, 226, 7) AS cnab_reserved_field,
    SUBSTRING(metadata, 144, 6) AS hr_file_generated,
    TO_DATE(SUBSTRING(metadata, 136, 8), 'ddMMyyyy') AS dt_file_generated,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial_extracts
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND id_bank IN (341, 237)
    AND id_service_batch = '0000'
    AND record_type = 0
    AND SUBSTRING(metadata, 156, 3) IN ('050', '030')
