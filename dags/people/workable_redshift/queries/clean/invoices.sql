SELECT
    -- ids
    id,
    purchased_posting_id AS id_purchased_posting,
    refund_id AS id_refund,

    -- non-metrics
    reference_code,
    purchase_type,
    amount_currency,
    billing_company,
    billing_company_vat,
    billing_address,
    billing_city,
    billing_zip,
    billing_state,
    billing_country_code,

    -- metrics
    CAST(amount AS DECIMAL(18, 2)) AS amount,
    CAST(discount AS DECIMAL(18, 2)) AS discount,
    CAST(amount_vat AS DECIMAL(18, 2)) AS amount_vat,
    CAST(amount_total AS DECIMAL(18, 2)) AS amount_total,

    -- date & timestamps
    TO_DATE(billing_date) AS dt_billed,
    TO_TIMESTAMP(invoice_created_at) AS ts_invoice_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load,

    -- partitions
    year,
    month,
    day

FROM
    datalake_workable_redshift_raw.invoices
WHERE 
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY 
    updated_at = MAX(updated_at) OVER (PARTITION BY id)