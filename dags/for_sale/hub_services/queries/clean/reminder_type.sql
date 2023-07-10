SELECT 
    id,
    name,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_hub_services_raw.reminder_type
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}