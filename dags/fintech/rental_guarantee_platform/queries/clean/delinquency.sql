SELECT
    CAST(id AS BIGINT) AS id,
    CAST(propose AS BIGINT) AS id_propose,
    status AS id_status,
    type AS id_type,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    CASE
      WHEN id_status = 0 THEN 'REGISTERED'
      WHEN id_status = 1 THEN 'RECOVERING' 
      WHEN id_status = 2 THEN 'PROGRESS' 
      WHEN id_status = 3 THEN 'FINISHED' 
      WHEN id_status = 4 THEN 'UNDER_AGREEMENT' 
      WHEN id_status = 5 THEN 'REQUESTED_AGREEMENT' 
      WHEN id_status = 6 THEN 'ACTIVE_FALSE' 
      WHEN id_status = 7 THEN 'FORGIVEN' 
    END AS status,
    CASE
      WHEN id_type = 0 THEN 'SIGNATURE'
      WHEN id_type = 1 THEN 'GUARANTEE'
      WHEN id_type = 2 THEN 'TERMINATION'
      WHEN id_type = 3 THEN 'BILLING'
      WHEN id_type = 4 THEN 'RENEWAL'
      WHEN id_type = 5 THEN 'RENEWAL_MONTH'
      WHEN id_type = 6 THEN 'ACTIVATION_PARTIAL_LINK'
    END AS type,
    subcategory,
    source,
    value,
    original_value,
    amount_paid,
    boleto_value AS bill_value,
    active AS is_active,
    valid AS is_valid,
    legacy_agreement AS is_legacy_agreement,
    due_date AS dt_due,
    boleto_month AS dt_bill_month,
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
