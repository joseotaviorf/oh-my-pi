WITH deleted_rows AS (
    SELECT
        id_address AS id_address_deleted_row,
        id_address AS id_company_deleted_row
    FROM
        datalake_company_clean.company_address_aud
    WHERE
        rev_type = 2
)
SELECT
    address_id AS id_address,
    company_id AS id_company,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.company_address AS a
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_address_deleted_row = a.address_id
        AND dr.id_company_deleted_row = a.company_id
WHERE
    dr.id_address_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_address, id_company ORDER BY ts_updated DESC) = 1
