SELECT
    id AS id_broker_integration_ingestion,
    broker_integration_id AS id_broker_integration,
    status,
    parent_ingestion_id AS id_parent_broker_integration_ingestion,
    total_rows,
    started_at AS ts_started,
    finished_at AS ts_finished,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.broker_integration_ingestion
