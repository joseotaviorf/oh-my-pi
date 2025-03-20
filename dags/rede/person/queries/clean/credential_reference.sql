SELECT
    id,
    person_id AS id_person,
    ref_id AS id_reference,
    origin,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.credential_reference