SELECT
    id,
    person_id AS id_person,
    ref_id AS id_reference,
    origin,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    person_id_mod AS mod_id_person,
    ref_id_mod AS mod_id_reference,
    origin_mod AS mod_origin,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_person_raw.credential_reference_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}