SELECT
    id,
    insurance_id AS id_insurance,
    version,
    payload,
    status,
    TIMESTAMP(synced_at) AS ts_synced,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.certificate_request
