SELECT 
    id_bank,
    id_service_batch,
    record_type,
    record_sequence_number,
    segment_type,
    metadata as description,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.cnab_payments
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'