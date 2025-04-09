SELECT
    id,
    idempotency_id AS id_idempotency,
    source_type_code,
    status,
    version,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.insurance
