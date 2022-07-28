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
    year = {year}
    AND month = {month}
    AND day = {day}
