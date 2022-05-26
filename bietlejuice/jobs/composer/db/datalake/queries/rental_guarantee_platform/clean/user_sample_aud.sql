SELECT
    id,
    name,
    email,
    main_phone,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    name_mod AS mod_name,
    email_mod AS mod_email,
    main_phone_mod AS mod_main_phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.user_sample_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}