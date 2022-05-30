SELECT
    id,
    person_id AS id_person,
    timezone,
    language,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    person_id_mod AS mod_id_person,
    timezone_mod AS mod_timezone,
    language_mod AS mod_language,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_person_raw.preference_settings_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}