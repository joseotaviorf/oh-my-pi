SELECT
    id,
    person_id AS id_person,
    value,
    scope,
    type,
    validation_type,
    version,
    last_validated_at AS ts_last_validated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.person_identity
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'