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
    datalake_company_raw.company_address
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'