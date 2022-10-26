SELECT
    id,
    visitor_id AS id_visitor,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    version,
    creator_email,
    created_by,
    creator_name,
    value,
    value_mod AS mod_value,
    visitor_id_mod AS mod_id_visitor,
    created_by_mod AS mod_created_by,
    creator_name_mod AS mod_creator_name,
    creator_email_mod AS mod_creator_email,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.observation_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}