SELECT
    id,
    external_id AS id_external,
    name AS user_name,
    email AS user_email,
    phone AS user_phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_owner_fees_raw.users
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
