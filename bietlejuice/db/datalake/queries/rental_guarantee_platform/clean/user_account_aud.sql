SELECT
    id,
    personuuid AS uuid_person,
    email,
    status,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    email_mod AS mod_email,
    personuuid_mod AS mod_uuid_person,
    status_mod AS mod_status,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.user_account_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}