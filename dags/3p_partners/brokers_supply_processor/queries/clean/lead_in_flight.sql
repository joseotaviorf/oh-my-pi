SELECT
    lead_id AS id_lead,
    group_id AS id_group,
    status,
    TRUE AS has_3p_access_control,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.lead_in_flight