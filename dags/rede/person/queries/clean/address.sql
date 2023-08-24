WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_person_clean.address_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    person_id AS id_person,
    country,
    state,
    city,
    neighborhood,
    address,
    zip_code,
    complement,
    number,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.address AS a
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = a.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
