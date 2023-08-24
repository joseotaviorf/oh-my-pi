WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_person_clean.right_to_be_forgotten_aud
    WHERE
        rev_type = 2
)
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
    datalake_person_raw.right_to_be_forgotten AS r
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = r.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
