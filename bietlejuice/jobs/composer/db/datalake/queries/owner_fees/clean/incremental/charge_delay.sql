SELECT
    id,
    waiting_period,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_owner_fees_raw.charge_delay
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}