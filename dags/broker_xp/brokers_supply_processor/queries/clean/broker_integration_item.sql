SELECT
    id AS id_broker_integration_item,
    broker_integration_id AS id_broker_integration,
    broker_source_id,
    payload_hash,
    latest_payload,
    status,
    operation,
    source_modified_at AS ts_source_modified,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.broker_integration_item
