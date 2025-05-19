SELECT
    id,
    person_id AS id_person,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.right_to_be_forgotten