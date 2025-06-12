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
    year,
    month,
    day
FROM
    datalake_signatures_test_raw.signature_collector
