SELECT
    id,
    propose AS id_propose,
    link,
    flow_type,
    user_insert,
    installments,
    version,
    active,
    due_date AS dt_due,
    expired AS ts_expired,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_guarantee_platform_raw.bill
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
