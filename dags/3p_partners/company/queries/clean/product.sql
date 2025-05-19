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
    datalake_company_raw.product