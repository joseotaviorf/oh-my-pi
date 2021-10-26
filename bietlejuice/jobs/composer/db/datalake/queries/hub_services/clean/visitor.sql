SELECT
    id,
    version,
    name AS visitor_name,
    email,
    phone_number,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.visitor
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}