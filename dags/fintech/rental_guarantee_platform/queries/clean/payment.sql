SELECT
    id,
    propose AS id_propose,
    customer,
    subscription,
    payment_link,
    invoice_url,
    unicid,
    description,
    gateway,
    version,
    status,
    billing_type,
    value,
    net_value,
    active AS is_active,
    due_date AS ts_due,
    original_due_date AS ts_due_original,
    client_payment_date AS ts_client_payment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.payment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
