SELECT
    id,
    payment_id AS id_payment,
    hook_type,
    hook_payload_response,
    version,
    hook_date AS ts_hook,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_payment_hook_history
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
