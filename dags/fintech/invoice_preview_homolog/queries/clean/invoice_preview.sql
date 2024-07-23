SELECT
    CAST(NULLIF(`contract-id`, '') AS bigint) AS id_contract,
    NULLIF(`version`, '') AS contract_version,
    NULLIF(`from`, '') AS paid_from,
    NULLIF(`to`, '') AS paid_to,
    NULLIF(description, '') AS payment_description,
    NULLIF(item, '') AS item_category,
    NULLIF(`tenant-status`, '') AS tenant_status,
    NULLIF(`landlord-status`, '') AS landlord_status,
    NULLIF(purpose, '') AS payment_purpose,
    NULLIF(country, '') AS country,
    CAST(NULLIF(REPLACE(REPLACE(amount, '.', ''), ',', '.'), '') AS double) AS paid_amount,
    CAST(NULLIF(`blocked`, '') AS BOOLEAN) AS is_blocked,
    CAST(NULLIF(`year-month`, '') AS bigint) AS entry_accrual_year_month,
    ELEMENT_AT(SPLIT(invoice_filename, '(invoice-preview-)|(-\\d{{2}}\\.csv)' ), -2) AS invoice_accrual_year_month,
    TO_DATE(NULLIF(`due-date`, ''), 'y-M-d') AS dt_due,
    TO_DATE(NULLIF(`tenant-due-date`, ''), 'y-M-d') AS dt_tenant_due,
    TO_DATE(NULLIF(`tenant-paid-date`, ''), 'y-M-d') AS dt_tenant_paid,
    TO_DATE(NULLIF(`landlord-due-date`, ''), 'y-M-d') AS dt_landlord_due,
    TO_DATE(NULLIF(`landlord-paid-date`, ''), 'y-M-d') AS dt_landlord_paid,
    TO_DATE(NULLIF(`tenant-invoice-created-at`, ''), 'y-M-d') AS dt_tenant_invoice_created_at,
    TO_DATE(NULLIF(`landlord-invoice-created-at`, ''), 'y-M-d') AS dt_landlord_invoice_created_at,
    year,
    month,
    day,
    ts_load
FROM
    datalake_invoice_preview_homolog_raw.invoice_preview
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
