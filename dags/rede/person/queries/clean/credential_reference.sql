WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_person_clean.credential_reference_aud
    WHERE
        rev_type = 2
)
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
    datalake_person_raw.credential_reference AS c
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = c.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
