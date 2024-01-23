WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_company_clean.company_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    parent_id AS id_parent,
    company_uuid AS uuid_company,
    company_name,
    trade_name,
    company_type,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.company AS c
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = c.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
