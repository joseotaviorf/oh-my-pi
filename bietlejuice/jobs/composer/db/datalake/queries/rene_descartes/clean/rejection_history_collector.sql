SELECT
    id,
    phone AS phone_number,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rene_descartes_raw.rejection_history_collector