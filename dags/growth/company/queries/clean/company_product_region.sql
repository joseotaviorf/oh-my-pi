SELECT
    id,
    company_id AS id_company,
    product_id AS id_product,
    region_external_id AS id_region,
    purpose,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.company_product_region
