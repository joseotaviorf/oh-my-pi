WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_company_clean.member_profile_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    profile_id AS id_profile,
    person_uuid AS uuid_person,
    company_product_product_id AS id_product,
    company_product_company_id AS id_company,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.member_profile AS m
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = m.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1

