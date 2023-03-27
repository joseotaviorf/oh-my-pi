SELECT
    id,
    version,
    subscription_code,
    subscription_status,
    card_brand,
    card_last_four_digits,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    active AS is_active,
    subscription_code_mod AS mod_subscription_code,
    subscription_status_mod AS mod_subscription_status,
    card_brand_mod AS mod_card_brand,
    card_last_four_digits_mod AS mod_card_last_four_digits,
    active_mod AS mod_is_active,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.subscription_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
