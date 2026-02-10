SELECT
    id,
    company_id AS id_company,
    product_id AS id_product,
    tier_id AS id_tier,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.company_product_tier