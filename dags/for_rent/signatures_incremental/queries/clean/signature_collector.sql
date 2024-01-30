SELECT
    id,
    external_reference_id AS id_external_reference,
    external_reference_name,
    version,
    status,
    started_at AS ts_started,
    completed_at AS ts_completed,
    sent_at AS ts_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_signatures_raw.signature_collector
WHERE
    date(updated_at) = date('{year}-{month}-{day}')