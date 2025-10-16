SELECT
    id,
    lead_id AS id_lead,
    operation,
    metadata,
    user_identification,
    reason,
    deleted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.lead_update_operation_history