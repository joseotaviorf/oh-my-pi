SELECT
    id,
    certificate_id AS id_certificate,
    idempotency_id AS id_idempotency,
    hash,
    status,
    event_type,
    DATE(event_date) AS dt_event,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.reminder
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
