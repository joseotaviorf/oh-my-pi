WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_company_clean.profile_hierarchy_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    profile_id AS id_profile,
    product_id AS id_product,
    position_number,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.profile_hierarchy AS p 
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = p.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1