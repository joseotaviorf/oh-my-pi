WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_company_clean.product_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    product_uuid AS uuid_product,
    name,
    status,
    business_segment,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.product AS p
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = p.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
