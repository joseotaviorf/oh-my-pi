SELECT
    id,
    visitor_id AS id_visitor,
    creator_id AS id_creator,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    version,
    value,
    value_mod AS mod_value,
    visitor_id_mod AS mod_id_visitor,
    creator_id_mod AS mod_id_creator,
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
