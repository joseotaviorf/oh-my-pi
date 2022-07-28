SELECT
    id,
    payment_id AS id_payment,
    hook_type,
    hook_payload_response,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    payment_id_mod AS mod_id_payment,
    hook_type_mod AS mod_hook_type,
    hook_payload_response_mod AS mod_hook_payload_response,
    hook_date_mod AS mod_ts_hook,
    hook_date AS ts_hook,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_payment_hook_history_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}