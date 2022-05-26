SELECT
    id,
    zip_code,
    street,
    complement,
    neighborhood,
    city,
    state,
    country,
    address_type,
    version,
    number,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.address
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}