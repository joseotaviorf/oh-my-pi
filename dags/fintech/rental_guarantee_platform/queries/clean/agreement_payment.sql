SELECT
    id,
    agreement_id AS id_agreement,
    status,
    billing_type,
    version,
    value,
    paid_value,
    due_date AS dt_due,
    paid_date AS dt_paid,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.agreement_payment

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
