SELECT
    CAST(id AS BIGINT) AS id,
    CAST(propose AS BIGINT) AS id_propose,
    status AS id_status,
    type AS id_type,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    subcategory,
    value,
    original_value,
    amount_paid,
    active AS is_active,
    valid AS is_valid,
    legacy_agreement AS is_legacy_agreement,
    due_date AS dt_due,
    payment_date AS dt_paid,
    schedule_payment_date AS dt_payment_scheduled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.delinquency

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
