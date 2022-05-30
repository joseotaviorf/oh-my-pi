SELECT
    id,
    profile_name,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    profile_name_mod AS mod_profile_name,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_company_raw.profile_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}