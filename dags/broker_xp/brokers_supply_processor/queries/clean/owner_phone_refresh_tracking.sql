SELECT
    id,
    person_uuid AS uuid_person,
    lead_uuid AS uuid_lead,
    status,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.owner_phone_refresh_tracking
