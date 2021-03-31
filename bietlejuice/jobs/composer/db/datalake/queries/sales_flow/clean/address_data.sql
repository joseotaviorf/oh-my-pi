SELECT
    id,
    street,
    number,
    complement,
    neighborhood,
    city,
    state,
    zip_code,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.address_data
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}