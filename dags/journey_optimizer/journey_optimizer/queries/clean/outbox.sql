SELECT
    id,
    event_id AS id_event,
    aggregate_id AS id_aggregate,
    aggregate_type,
    event_type,
    event_data,
    topic,
    status,
    last_error,
    retry_count,
    created_at AS ts_created,
    processing_started_at AS ts_processing_started,
    published_at AS ts_published
FROM
    datalake_journey_optimizer_raw.outbox
