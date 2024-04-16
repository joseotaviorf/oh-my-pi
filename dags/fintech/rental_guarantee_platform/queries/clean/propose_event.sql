SELECT
    id,
    entity_id AS id_entity,
    event_type,
    payload,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.propose_event
