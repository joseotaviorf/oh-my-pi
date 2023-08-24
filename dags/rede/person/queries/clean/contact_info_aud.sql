SELECT
    id,
    contactuuid AS uuid_contact,
    person_id AS id_person,
    contact_info,
    category,
    extra_info,
    priority,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    is_active,
    person_id_mod AS mod_id_person,
    contactuuid_mod AS mod_uuid_contact,
    contact_info_mod AS mod_contact_info,
    category_mod AS mod_category,
    extra_info_mod AS mod_contact_preferences,
    priority_mod AS mod_priority,
    is_active_mod AS mod_is_active,
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