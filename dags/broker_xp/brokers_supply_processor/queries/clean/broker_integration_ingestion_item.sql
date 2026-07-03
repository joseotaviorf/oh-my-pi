SELECT
    id AS id_broker_integration_ingestion_item,
    ingestion_id AS id_broker_integration_ingestion,
    broker_source_id,
    row_index,
    payload,
    payload_hash,
    source_modified_at AS ts_source_modified,
    status,
    status_message,
    retry_count,
    next_retry_at AS ts_next_retry,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.broker_integration_ingestion_item
