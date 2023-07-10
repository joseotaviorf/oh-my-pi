SELECT
    id,
    visitor_id AS id_visitor,
    house_id AS id_house,
    region_id AS id_region,
    user_id AS id_user,
    idempotency_id AS id_idempotency,
    domain_name,
    event_type,
    event_code,
    metadata,
    version,
    event_date AS ts_event,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.visitor_event
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}