SELECT
    id,
    version,
    status,
    external_id AS id_external,
    external_system,
    amount,
    description,
    reason,
    purpose,
    refunded_item_id AS id_refunded_item,
    insurance_id AS id_insurance,
    accrual_year_month,
    DATE(accrued_date) AS dt_accrued,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.tenant_invoice_item
