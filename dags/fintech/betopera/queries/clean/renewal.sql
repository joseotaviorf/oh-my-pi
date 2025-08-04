SELECT
    id,
    certificate_id AS id_certificate,
    type,
    DATE(start_date) AS dt_start,
    DATE(end_date) AS dt_end,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.renewal
