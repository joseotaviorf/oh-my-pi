SELECT
    id,
    payment_id      AS id_payment,
    price_index,
    price_index_type,
    step,
    cycle,
    version,
    propose,
    previous_monthly_amount,
    updated_monthly_amount,
    due_date        AS dt_due,
    paid_date       AS dt_paid,
    created_at      AS ts_created,
    updated_at      AS ts_updated
FROM
    datalake_rental_guarantee_platform_raw.renewal
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
