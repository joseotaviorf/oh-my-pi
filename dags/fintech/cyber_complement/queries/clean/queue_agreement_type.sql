SELECT
    AQTYPE AS id_agreement_type,
    AQQUE AS id_queue,
    NOW() AS ts_load
FROM datalake_cyber_raw.agrvalq
