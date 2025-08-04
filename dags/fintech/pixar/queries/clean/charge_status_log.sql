SELECT
    id,
    charge_id AS id_charge,
    status,
    bank_response,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(processed_at) AS ts_processed
FROM
    datalake_pixar_raw.charge_status_log
