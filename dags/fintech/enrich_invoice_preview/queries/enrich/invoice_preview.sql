WITH source AS (
    SELECT
        id_contract,
        contract_version,
        is_blocked,
        paid_from,
        paid_to,
        payment_description,
        paid_amount,
        item_category,
        entry_accrual_year_month,
        dt_due,
        dt_tenant_due,
        dt_tenant_paid,
        tenant_status,
        dt_landlord_due,
        dt_landlord_paid,
        landlord_status,
        payment_purpose,
        dt_tenant_invoice_created_at,
        dt_landlord_invoice_created_at,
        ts_load,
        invoice_accrual_year_month,
        country,
        year,
        month,
        day
    FROM
        datalake_invoice_preview_clean.invoice_preview
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND country = 'BR'
),
latest_load_per_day AS (
    SELECT
        year,
        month,
        day,
        MAX(ts_load) AS ts_load
    FROM
        source
    GROUP BY
        year,
        month,
        day
)
SELECT
    s.id_contract,
    s.contract_version,
    s.is_blocked AS blocked,
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
    s.invoice_accrual_year_month,
    s.country,
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
INNER JOIN latest_load_per_day AS l
    ON s.year = l.year
    AND s.month = l.month
    AND s.day = l.day
    AND s.ts_load = l.ts_load
