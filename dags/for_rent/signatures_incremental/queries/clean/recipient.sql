SELECT
    id,
    internal_reference_id AS id_internal_reference,
    external_reference_id AS id_external_reference,
    internal_reference_name,
    external_reference_name,
    version,
    name,
    email,
    dtype AS type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_signatures_raw.recipient
WHERE
    date(updated_at) = date('{year}-{month}-{day}')