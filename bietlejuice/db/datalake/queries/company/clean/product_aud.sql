SELECT
    id,
    company_id AS id_company,
    product_uuid AS uuid_product,
    name,
    status,
    business_segment,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    product_uuid_mod AS mod_uuid_product,
    name_mod AS mod_name,
    status_mod AS mod_status,
    business_segment_mod AS mod_business_segment,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_company_raw.product_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
