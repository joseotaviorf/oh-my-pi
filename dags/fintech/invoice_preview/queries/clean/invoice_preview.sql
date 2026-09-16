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
    NULLIF(`last-modified-by-name`, '') AS last_modified_by_name,
    NULLIF(`last-modified-by-email`, '') AS last_modified_by_email,
    CAST(NULLIF(REPLACE(REPLACE(amount, '.', ''), ',', '.'), '') AS double) AS paid_amount,
    CAST(NULLIF(`blocked`, '') AS BOOLEAN) AS is_blocked,
    CAST(NULLIF(`not-invoiceable`, '') AS BOOLEAN) AS is_not_invoiceable,
    CAST(NULLIF(`year-month`, '') AS bigint) AS entry_accrual_year_month,
    NULLIF(invoice_filename, '') AS invoice_filename,
    ELEMENT_AT(SPLIT(invoice_filename, '(invoice-preview-)|(-\\d{{2}}\\.csv)' ), -2) AS invoice_accrual_year_month,
    CASE
        WHEN HOUR(
            FROM_UTC_TIMESTAMP(
                TO_TIMESTAMP(CAST(REGEXP_EXTRACT(invoice_filename, '([0-9]+)-', 1) AS BIGINT)),
                'America/Sao_Paulo'
            )
        ) >= 12 THEN 'afternoon'
        ELSE 'morning'
    END AS export_slot,
    TO_DATE(NULLIF(`due-date`, ''), 'y-M-d') AS dt_due,
    TO_DATE(NULLIF(`tenant-due-date`, ''), 'y-M-d') AS dt_tenant_due,
    TO_DATE(NULLIF(`tenant-paid-date`, ''), 'y-M-d') AS dt_tenant_paid,
    TO_DATE(NULLIF(`landlord-due-date`, ''), 'y-M-d') AS dt_landlord_due,
    TO_DATE(NULLIF(`landlord-paid-date`, ''), 'y-M-d') AS dt_landlord_paid,
    TO_DATE(NULLIF(`tenant-invoice-created-at`, ''), 'y-M-d') AS dt_tenant_invoice_created_at,
    TO_DATE(NULLIF(`landlord-invoice-created-at`, ''), 'y-M-d') AS dt_landlord_invoice_created_at,
    TO_TIMESTAMP(NULLIF(`created-at`, '')) AS ts_created,
    year,
    month,
    day,
    ts_load
FROM
    datalake_invoice_preview_raw.invoice_preview
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
