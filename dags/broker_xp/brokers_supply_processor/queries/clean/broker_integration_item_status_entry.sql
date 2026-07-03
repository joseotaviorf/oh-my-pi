SELECT
    id AS id_broker_integration_item_status_entry,
    broker_integration_item_id AS id_broker_integration_item,
    status,
    message,
    occurred_at AS ts_occurred,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.broker_integration_item_status_entry
