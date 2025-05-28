SELECT
    id,
    tracking_id AS id_tracking,
    event_uuid AS uuid_event,
    lead_uuid AS uuid_lead,
    event_type,
    event_properties,
    event_date AS ts_event,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.analytic_event