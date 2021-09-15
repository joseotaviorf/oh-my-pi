SELECT
    id,
    enrollment_id AS id_enrollment,
    house_id AS id_house,
    rev,
    revend AS rev_end,
    revtype AS rev_type,    
    details,
    since,
    enrollment_mod AS mod_enrollment,
    house_mod AS mod_house,
    details_mod AS mod_details,
    since_mod AS mod_since,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.agency_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
