SELECT
    id,
    propose AS id_propose,
    unicid,
    version,
    value,
    net_value,
    fine_value,
    interest_value,
    billing_type,
    status,
    invoice_url,
    payment_link,
    description,
    raw_response AS json_raw_response,
    due_date AS dt_due,
    original_due_date AS dt_due_original,
    client_payment_date AS dt_client_payment,
    confirmed_payment_date AS dt_confirmed_payment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.agreement_payment_legacy

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
