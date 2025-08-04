SELECT
    id_bank,
    id_service_batch,
    record_type,
    SUBSTRING(metadata, 1, 5) AS record_sequence_number,
    SUBSTRING(metadata, 6, 1) AS segment_type,
    SUBSTRING(metadata, 7, 3) AS instruction_code,
    SUBSTRING(metadata, 10, 3) AS compensation_code,
    metadata AS description,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial_extracts
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND record_type = 3
