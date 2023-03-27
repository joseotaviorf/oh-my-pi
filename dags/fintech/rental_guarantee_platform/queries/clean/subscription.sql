SELECT
    id,
    version,
    subscription_code,
    subscription_status,
    card_brand,
    card_last_four_digits,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.subscription
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
