-- Snapshot BR of the latest clean partition day + morning export_slot (max ts_load).
-- Date choice stays MAX(MAKE_DATE) WHERE country = 'BR', limited to the last 5 BRT days
-- so Spark can prune partitions (today, else yesterday if today has no BR rows).
-- Morning rows of that day are read once; MAX(ts_load) is a window on that scan.
WITH window_bounds AS (
    SELECT
        DATE_SUB(dt_as_of, 5) AS dt_lookback,
        dt_as_of
    FROM (
        SELECT
            TO_DATE(FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP(), 'America/Sao_Paulo')) AS dt_as_of
    ) AS as_of
),
latest_partition AS (
    SELECT
        YEAR(load_date) AS year,
        MONTH(load_date) AS month,
        DAY(load_date) AS day
    FROM (
        SELECT
            MAX(MAKE_DATE(clean_preview.year, clean_preview.month, clean_preview.day)) AS load_date
        FROM
            datalake_invoice_preview_clean.invoice_preview AS clean_preview
        CROSS JOIN window_bounds
        WHERE
            clean_preview.country = 'BR'
            AND (
                clean_preview.year > YEAR(window_bounds.dt_lookback)
                OR (
                    clean_preview.year = YEAR(window_bounds.dt_lookback)
                    AND clean_preview.month > MONTH(window_bounds.dt_lookback)
                )
                OR (
                    clean_preview.year = YEAR(window_bounds.dt_lookback)
                    AND clean_preview.month = MONTH(window_bounds.dt_lookback)
                    AND clean_preview.day >= DAY(window_bounds.dt_lookback)
                )
            )
            AND (
                clean_preview.year < YEAR(window_bounds.dt_as_of)
                OR (
                    clean_preview.year = YEAR(window_bounds.dt_as_of)
                    AND clean_preview.month < MONTH(window_bounds.dt_as_of)
                )
                OR (
                    clean_preview.year = YEAR(window_bounds.dt_as_of)
                    AND clean_preview.month = MONTH(window_bounds.dt_as_of)
                    AND clean_preview.day <= DAY(window_bounds.dt_as_of)
                )
            )
    )
),
morning_on_latest_day AS (
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
        clean_preview.day,
        MAX(clean_preview.ts_load) OVER () AS ts_load_latest
    FROM
        datalake_invoice_preview_clean.invoice_preview AS clean_preview
    INNER JOIN latest_partition
        ON clean_preview.year = latest_partition.year
        AND clean_preview.month = latest_partition.month
        AND clean_preview.day = latest_partition.day
    WHERE
        clean_preview.country = 'BR'
        AND COALESCE(clean_preview.export_slot, 'morning') = 'morning'
)
SELECT
    morning_on_latest_day.id_contract,
    morning_on_latest_day.contract_version,
    morning_on_latest_day.is_blocked AS blocked,
    morning_on_latest_day.is_not_invoiceable,
    morning_on_latest_day.paid_from,
    morning_on_latest_day.paid_to,
    morning_on_latest_day.payment_description,
    CASE
        WHEN morning_on_latest_day.paid_from IN ('Proprietario', 'Inquilino') THEN morning_on_latest_day.paid_amount * -1
        ELSE morning_on_latest_day.paid_amount
    END AS amount,
    morning_on_latest_day.item_category,
    morning_on_latest_day.entry_accrual_year_month AS year_month,
    morning_on_latest_day.dt_due,
    morning_on_latest_day.dt_tenant_due,
    morning_on_latest_day.dt_tenant_paid,
    morning_on_latest_day.tenant_status,
    morning_on_latest_day.dt_landlord_due,
    morning_on_latest_day.dt_landlord_paid,
    morning_on_latest_day.landlord_status,
    morning_on_latest_day.payment_purpose,
    morning_on_latest_day.dt_tenant_invoice_created_at,
    morning_on_latest_day.dt_landlord_invoice_created_at,
    morning_on_latest_day.ts_load,
    morning_on_latest_day.invoice_filename,
    morning_on_latest_day.invoice_accrual_year_month,
    morning_on_latest_day.country,
    morning_on_latest_day.last_modified_by_name,
    morning_on_latest_day.last_modified_by_email,
    morning_on_latest_day.ts_created,
    TRY_CAST(
        REVERSE(
            CASE
                WHEN morning_on_latest_day.payment_description LIKE '%arcela%'
                    THEN SPLIT_PART(REVERSE(morning_on_latest_day.payment_description), ' ed ', 1)
                ELSE '1'
            END
        ) AS BIGINT
    ) AS payment_installment,
    morning_on_latest_day.year,
    morning_on_latest_day.month,
    morning_on_latest_day.day
FROM
    morning_on_latest_day
WHERE
    morning_on_latest_day.ts_load = morning_on_latest_day.ts_load_latest
