SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    code,
    details,
    name,
    enrollments_mod AS mod_enrollments,
    code AS mod_code,
    details AS mod_details,
    name AS mod_name,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.program_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
