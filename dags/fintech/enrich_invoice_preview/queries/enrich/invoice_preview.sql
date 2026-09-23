-- Snapshot BR of the latest clean partition day + morning export_slot (max ts_load).
-- Date choice is unchanged: MAX(MAKE_DATE(year, month, day)) WHERE country = 'BR'.
-- Subsequent reads join year/month/day so Spark can prune partitions (MAKE_DATE in ON cannot).
WITH latest_partition AS (
    SELECT
        YEAR(load_date) AS year,
        MONTH(load_date) AS month,
        DAY(load_date) AS day
    FROM (
        SELECT
            MAX(MAKE_DATE(year, month, day)) AS load_date
        FROM
            datalake_invoice_preview_clean.invoice_preview
        WHERE
            country = 'BR'
    )
),
latest_morning_load AS (
    SELECT
        MAX(clean_preview.ts_load) AS ts_load
    FROM
        datalake_invoice_preview_clean.invoice_preview AS clean_preview
    INNER JOIN latest_partition
        ON clean_preview.year = latest_partition.year
        AND clean_preview.month = latest_partition.month
        AND clean_preview.day = latest_partition.day
    WHERE
        clean_preview.country = 'BR'
        AND COALESCE(clean_preview.export_slot, 'morning') = 'morning'
),
source AS (
    SELECT
        clean_preview.id_contract,
        clean_preview.contract_version,
        clean_preview.is_blocked,
        clean_preview.is_not_invoiceable,
        clean_preview.paid_from,
        clean_preview.paid_to,
        clean_preview.payment_description,
        clean_preview.paid_amount,
        clean_preview.item_category,
        clean_preview.entry_accrual_year_month,
        clean_preview.dt_due,
        clean_preview.dt_tenant_due,
        clean_preview.dt_tenant_paid,
        clean_preview.tenant_status,
        clean_preview.dt_landlord_due,
        clean_preview.dt_landlord_paid,
        clean_preview.landlord_status,
        clean_preview.payment_purpose,
        clean_preview.dt_tenant_invoice_created_at,
        clean_preview.dt_landlord_invoice_created_at,
        clean_preview.ts_load,
        clean_preview.invoice_filename,
        clean_preview.invoice_accrual_year_month,
        clean_preview.country,
        clean_preview.last_modified_by_name,
        clean_preview.last_modified_by_email,
        clean_preview.ts_created,
        clean_preview.year,
        clean_preview.month,
        clean_preview.day
    FROM
        datalake_invoice_preview_clean.invoice_preview AS clean_preview
    INNER JOIN latest_partition
        ON clean_preview.year = latest_partition.year
        AND clean_preview.month = latest_partition.month
        AND clean_preview.day = latest_partition.day
    INNER JOIN latest_morning_load
        ON clean_preview.ts_load = latest_morning_load.ts_load
    WHERE
        clean_preview.country = 'BR'
        AND COALESCE(clean_preview.export_slot, 'morning') = 'morning'
)
SELECT
    source.id_contract,
    source.contract_version,
    source.is_blocked AS blocked,
    source.is_not_invoiceable,
    source.paid_from,
    source.paid_to,
    source.payment_description,
    CASE
        WHEN source.paid_from IN ('Proprietario', 'Inquilino') THEN source.paid_amount * -1
        ELSE source.paid_amount
    END AS amount,
    source.item_category,
    source.entry_accrual_year_month AS year_month,
    source.dt_due,
    source.dt_tenant_due,
    source.dt_tenant_paid,
    source.tenant_status,
    source.dt_landlord_due,
    source.dt_landlord_paid,
    source.landlord_status,
    source.payment_purpose,
    source.dt_tenant_invoice_created_at,
    source.dt_landlord_invoice_created_at,
    source.ts_load,
    source.invoice_filename,
    source.invoice_accrual_year_month,
    source.country,
    source.last_modified_by_name,
    source.last_modified_by_email,
    source.ts_created,
    TRY_CAST(
        REVERSE(
            CASE
                WHEN source.payment_description LIKE '%arcela%'
                    THEN SPLIT_PART(REVERSE(source.payment_description), ' ed ', 1)
                ELSE '1'
            END
        ) AS BIGINT
    ) AS payment_installment,
    source.year,
    source.month,
    source.day
FROM
    source
