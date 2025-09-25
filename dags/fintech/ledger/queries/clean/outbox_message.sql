SELECT 
    id AS id_outbox_message, 
    aggregate_id AS id_aggregate, 
    partition_key, 
    aggregate_type, 
    event_type, 
    payload, 
    tracing_span_context, 
    created_at_unix, 
    TIMESTAMP(created_at) AS ts_created_at
FROM 
    datalake_ledger_raw.outbox_message