SELECT
    id,
    person_id AS id_person,
    contact_info,
    category,
    contact_preferences,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    person_id_mod AS mod_id_person,
    contact_info_mod AS mod_contact_info,
    category_mod AS mod_category,
    contact_preferences_mod AS mod_contact_preferences,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_person_raw.contact_info_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}