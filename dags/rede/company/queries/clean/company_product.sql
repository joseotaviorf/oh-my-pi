SELECT
    company_id AS id_company,
    product_id AS id_product,
    product_settings
FROM
    datalake_company_raw.company_product
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'