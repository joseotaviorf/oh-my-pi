SELECT
    id,
    version,
    name AS user_name,
    email,
    main_phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.user_sample
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}