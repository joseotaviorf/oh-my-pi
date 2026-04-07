SELECT
    id,
    event_entity_id AS id_event_entity,
    company_uuid AS uuid_company,
    person_uuid AS uuid_person,
    application_source,
    event_entity_name,
    event_type,
    trigger_actor,
    event_time AS ts_event,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.buyer_company_event