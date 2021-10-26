SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    version,
    name AS user_name,
    email,
    main_phone,
    name_mod AS mod_user_name,
    email_mod AS mod_email,
    main_phone_mod AS mod_main_phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.user_sample_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}