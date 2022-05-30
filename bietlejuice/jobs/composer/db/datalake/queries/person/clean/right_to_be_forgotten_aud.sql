SELECT
    id,
    person_id AS id_person,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    person_id_mod AS mod_id_person,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_person_raw.right_to_be_forgotten_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}