SELECT
    id,
    contactuuid AS uuid_contact,
    person_id AS id_person,
    contact_info,
    category,
    extra_info,
    priority,
    version,
    is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.contact_info
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'