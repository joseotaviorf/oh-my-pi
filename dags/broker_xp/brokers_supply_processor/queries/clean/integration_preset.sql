SELECT
    id AS uuid_integration_preset,
    name,
    description,
    type,
    file_parser,
    mapping,
    filter_rules,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.integration_preset
