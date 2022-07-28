SELECT
    id,
    name AS profile_name,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    name_mod AS mod_profile_name,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.profile_account_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}