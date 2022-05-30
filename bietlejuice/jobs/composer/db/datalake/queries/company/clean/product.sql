SELECT
    id,
    company_id AS id_company,
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
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}