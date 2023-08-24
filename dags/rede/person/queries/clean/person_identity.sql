WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_person_clean.person_identity_aud
    WHERE
        rev_type = 2
)
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
    datalake_person_raw.person_identity AS p
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = p.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1


