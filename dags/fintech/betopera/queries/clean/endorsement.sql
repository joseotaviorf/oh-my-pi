SELECT
    id,
    certificate_id AS id_certificate,
    process_info,
    type,
    status,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.endorsement
