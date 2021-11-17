SELECT
    id,
    location,
    phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.access_info
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}