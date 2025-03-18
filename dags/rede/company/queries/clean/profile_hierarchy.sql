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
    datalake_company_raw.profile_hierarchy
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'