WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_company_clean.user_requirements_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    company_id AS id_company,
    requirements,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.user_requirements AS u
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = u.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
