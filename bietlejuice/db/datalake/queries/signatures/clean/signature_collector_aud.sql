SELECT
    id AS id_signature_collector,
    external_reference_id AS id_external_reference,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    external_reference_name,
    version,
    status,
    external_reference_mod AS mod_id_external_reference,
    status_mod AS mod_status,
    started_at_mod AS mod_ts_started,
    completed_at_mod AS mod_ts_completed,
    sent_at_mod AS mod_ts_sent,
    started_at AS ts_started,
    completed_at AS ts_completed,
    sent_at AS ts_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year(updated_at) AS year,
    month(updated_at) AS month,
    day(updated_at) AS day
FROM
    datalake_signatures_raw.signature_collector_aud
WHERE
    date(updated_at) = date('{year}-{month}-{day}')