SELECT
    id,
    batch_id AS id_batch,
    origin,
    batch_type,
    batch_payload,
    batch_size,
    started_at AS dt_started,
    finished_at AS dt_finished,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_trato_feito_raw.events_batch
