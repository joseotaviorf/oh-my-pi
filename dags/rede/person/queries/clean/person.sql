SELECT
    id,
    personuuid AS uuid_person,
    name AS person_name,
    gender,
    country_code,
    photo,
    version,
    blocked AS is_blocked,
    birth_date AS dt_birth,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.person
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'