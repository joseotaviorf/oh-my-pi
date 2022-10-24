SELECT
    id,
    contract_id AS id_contract,
    person_id AS id_person,
    card_token,
    card_service_tax_value,
    card_guarantee_value,
    card_four_last_digits,
    card_brand,
    card_token_payload_response,
    subscription_code,
    subscription_status,
    hook_type,
    version,
    card_created_at AS ts_card_created,
    subscription_status_last_update AS ts_subscription_status_last_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_payment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}