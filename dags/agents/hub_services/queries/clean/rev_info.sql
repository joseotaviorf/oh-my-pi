SELECT
    id,
    user_id AS id_user,
    TO_TIMESTAMP(timestamp/1000) AS ts_created,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.revinfo
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}