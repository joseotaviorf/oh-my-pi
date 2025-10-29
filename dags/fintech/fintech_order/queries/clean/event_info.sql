SELECT
    id,
    external_id AS id_external,
    source,
    event,
    generated_at AS ts_generated,
    created_at AS ts_created
FROM
    datalake_fintech_order_raw.event_info
