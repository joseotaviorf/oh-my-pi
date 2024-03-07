SELECT
    id,
    rev,
    revend AS rev_end, 
    revtype AS rev_type,
    metadata AS details,
    metadata_mod AS mod_details,
    enrollments_mod AS mod_enrollments,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.agent_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
