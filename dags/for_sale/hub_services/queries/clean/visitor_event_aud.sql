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
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    visitor_id_mod AS mod_id_visitor,
    house_id_mod AS mod_id_house,
    region_id_mod AS mod_id_region,
    user_id_mod AS mod_id_user,
    idempotency_id_mod AS mod_id_idempotency,
    domain_name_mod AS mod_domain_name,
    event_type_mod AS mod_event_type,
    event_code_mod AS mod_event_code,
    metadata_mod AS mod_metadata,
    event_date_mod AS mod_ts_event,
    event_date AS ts_event,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.visitor_event_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}