SELECT
    id,
    type,
    billing_report AS id_billing_report,
    propose,
    status,
    installment,
    amount,
    created_at  AS ts_created,
    updated_at  AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.entry
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
