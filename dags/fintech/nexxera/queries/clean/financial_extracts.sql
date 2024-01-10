SELECT
    id_bank,
    id_service_batch,
    record_type,
    SUBSTRING(metadata, 1, 5) AS record_sequence_number,
    SUBSTRING(metadata, 6, 1) AS segment_type,
    SUBSTRING(metadata, 7, 3) AS instruction_code,
    SUBSTRING(metadata, 10, 3) AS compensation_code,
    metadata AS description,
    NOW() AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial_extracts
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND record_type = 3
