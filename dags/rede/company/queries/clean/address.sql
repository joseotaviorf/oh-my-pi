SELECT
    id,
    company_uuid AS uuid_company,
    public_area,
    country,
    state,
    city,
    neighborhood,
    zip_code,
    number,
    complement,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.address
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'