SELECT
    id,
    personuuid AS uuid_person,
    name AS person_name,
    gender,
    country_code,
    photo,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    blocked AS is_blocked,
    personuuid_mod AS mod_uuid_person,
    name_mod AS mod_name,
    birth_date_mod AS mod_birth_date,
    gender_mod AS mod_gender,
    country_code_mod AS mod_country_code,
    photo_mod AS mod_photo,
    blocked_mod AS mod_is_blocked,
    birth_date AS dt_birth,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_person_raw.person_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}