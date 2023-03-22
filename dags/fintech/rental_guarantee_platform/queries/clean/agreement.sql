SELECT
    id,
    external_id AS id_external,
    status,
    type,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.agreement
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
