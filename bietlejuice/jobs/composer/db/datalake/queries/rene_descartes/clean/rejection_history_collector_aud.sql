SELECT
    id,
    phone AS phone_number,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rene_descartes_raw.rejection_history_collector_aud