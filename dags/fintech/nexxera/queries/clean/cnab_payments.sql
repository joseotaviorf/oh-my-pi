SELECT 
    id_bank,
    id_service_batch,
    record_type,
    record_sequence_number,
    segment_type,
    metadata as description,
    NOW() AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.cnab_payments
WHERE
    year = {year}
AND 
    month = {month}
AND 
    day = {day}