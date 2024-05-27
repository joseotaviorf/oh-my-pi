SELECT
    id,
    company      AS id_company,
    boleto       AS id_bill,
    status,
    total_amount,
    accrual_year,
    accrual_month,
    version_report,
    due_date    AS dt_due,
    created_at  AS ts_created,
    updated_at  AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.billing_report
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
