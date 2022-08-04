SELECT
    id,
    charge_id AS id_charge,
    amount,
    status,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_pixar_raw.refund
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
