SELECT
    CAST(id AS BIGINT) AS id,
    CAST(propose AS BIGINT) AS id_propose,
    CAST(subscription AS BIGINT) AS id_subscription,
    order_id AS id_order,
    charge_id AS id_charge,
    customer,
    card_token,
    code,
    payment_link,
    invoice_url,
    unicid,
    description,
    gateway,
    version,
    status,
    billing_type,
    product_type,
    installments,
    value,
    tax,
    refund_amount,
    active AS is_active,
    due_date AS ts_due,
    original_due_date AS ts_due_original,
    client_payment_date AS ts_client_payment,
    refunded_at AS ts_refunded,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.payment

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
