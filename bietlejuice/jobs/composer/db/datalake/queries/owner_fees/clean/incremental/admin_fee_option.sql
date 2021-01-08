SELECT
    id,
    admin_fee,
    starts_at AS dt_start,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_owner_fees_raw.admin_fee_option
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}