WITH latest_partition AS (
    SELECT
        MAX(MAKE_DATE(year, month, day)) AS load_date
    FROM
        datalake_invoice_preview_clean.invoice_preview
    WHERE
        country = 'BR'
),
latest_morning_load AS (
    SELECT
        MAX(c.ts_load) AS ts_load
    FROM
        datalake_invoice_preview_clean.invoice_preview AS c
    INNER JOIN latest_partition AS lp
        ON MAKE_DATE(c.year, c.month, c.day) = lp.load_date
    WHERE
        c.country = 'BR'
        AND COALESCE(c.export_slot, 'morning') = 'morning'
),
source AS (
    SELECT
        c.id_contract,
        c.contract_version,
        c.is_blocked,
        c.is_not_invoiceable,
        c.paid_from,
        c.paid_to,
        c.payment_description,
        c.paid_amount,
        c.item_category,
        c.entry_accrual_year_month,
        c.dt_due,
        c.dt_tenant_due,
        c.dt_tenant_paid,
        c.tenant_status,
        c.dt_landlord_due,
        c.dt_landlord_paid,
        c.landlord_status,
        c.payment_purpose,
        c.dt_tenant_invoice_created_at,
        c.dt_landlord_invoice_created_at,
        c.ts_load,
        c.invoice_filename,
        c.invoice_accrual_year_month,
        c.country,
        c.last_modified_by_name,
        c.last_modified_by_email,
        c.ts_created,
        c.year,
        c.month,
        c.day
    FROM
        datalake_invoice_preview_clean.invoice_preview AS c
    INNER JOIN latest_partition AS lp
        ON MAKE_DATE(c.year, c.month, c.day) = lp.load_date
    INNER JOIN latest_morning_load AS l
        ON c.ts_load = l.ts_load
    WHERE
        c.country = 'BR'
        AND COALESCE(c.export_slot, 'morning') = 'morning'
)
SELECT
    s.id_contract,
    s.contract_version,
    s.is_blocked AS blocked,
    s.is_not_invoiceable,
    s.paid_from,
    s.paid_to,
    s.payment_description,
    CASE
        WHEN s.paid_from IN ('Proprietario', 'Inquilino') THEN s.paid_amount * -1
        ELSE s.paid_amount
    END AS amount,
    s.item_category,
    s.entry_accrual_year_month AS year_month,
    s.dt_due,
    s.dt_tenant_due,
    s.dt_tenant_paid,
    s.tenant_status,
    s.dt_landlord_due,
    s.dt_landlord_paid,
    s.landlord_status,
    s.payment_purpose,
    s.dt_tenant_invoice_created_at,
    s.dt_landlord_invoice_created_at,
    s.ts_load,
    s.invoice_filename,
    s.invoice_accrual_year_month,
    s.country,
    s.last_modified_by_name,
    s.last_modified_by_email,
    s.ts_created,
    TRY_CAST(
        REVERSE(
            CASE
                WHEN s.payment_description LIKE '%arcela%'
                    THEN SPLIT_PART(REVERSE(s.payment_description), ' ed ', 1)
                ELSE '1'
            END
        ) AS BIGINT
    ) AS payment_installment,
    s.year,
    s.month,
    s.day
FROM
    source AS s
