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
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    contract_id_mod AS mod_id_contract,
    person_id_mod AS mod_id_person,
    card_token_mod AS mod_card_token,
    card_service_tax_value_mod AS mod_card_service_tax_value,
    card_guarantee_value_mod AS mod_card_guarantee_value,
    card_four_last_digits_mod AS mod_card_four_last_digits,
    card_brand_mod AS mod_card_brand,
    card_token_payload_response_mod AS mod_card_token_payload_response,
    subscription_code_mod AS mod_subscription_code,
    subscription_status_mod AS mod_subscription_status,
    hook_type_mod AS mod_hook_type,
    card_created_at_mod AS mod_ts_card_created,
    subscription_status_last_update_mod AS mod_ts_subscription_status_last_updated,
    card_created_at AS ts_card_created,
    subscription_status_last_update AS ts_subscription_status_last_updated,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_payment_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}