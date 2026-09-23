WITH contract AS (
    SELECT DISTINCT
        invoice_all.sk_contract,
        invoice_all.version,
        invoice_all.is_contract_b2b,
        invoice_all.guarantee,
        invoice_all.rental_administrator,
        invoice_all.invoice_canceled_date,
        invoice_all.contract_start,
        invoice_all.contract_annulment,
        invoice_all.ended_before_started,
        invoice_all.contract_status,
        dim_contract.status,
        country_code
    FROM
        datalake_accounting_funnel.invoice_all AS invoice_all
    LEFT JOIN
        dw_rent.dim_contract AS dim_contract
            ON invoice_all.sk_contract = dim_contract.sk_contract
),

rh_contract_info AS (
    SELECT DISTINCT
        c.sk_contract,
        ie.is_rental_paid_in_advance
    FROM
        dw_rent.dim_contract AS c
    LEFT JOIN
        dw_payment.fact_invoice_entries AS fie
            ON fie.sk_contract = c.sk_contract
    LEFT JOIN
        dw_payment.dim_invoice_entry AS ie
            ON ie.sk_invoice_entry = fie.sk_invoice_entry
),

recon_removal AS (
    SELECT
        id_accounting_entry,
        reason,
        ts_created
    FROM (
        SELECT
            id_accounting_entry,
            reason,
            ts_created,
            ROW_NUMBER() OVER (
                PARTITION BY id_accounting_entry
                ORDER BY ts_created DESC, ts_cdc_transaction DESC, id DESC
            ) AS rni
        FROM
            datalake_robin_hood_clean.accounting_entry_recon_removals
    )
    WHERE
        rni = 1
),

rh_all AS (
    SELECT
        eb.id_accounting_entry,
        CAST(NULL AS BIGINT) AS id_entry,
        CAST(NULL AS BIGINT) AS id_invoice,
        TRY_CAST(COALESCE(ae.id_contract, regexp_replace(ae.description, '[^0-9]', '')) AS BIGINT) AS sk_contract,
        COALESCE(split(c.version, '.')[1], 'no info') AS version,
        c.is_contract_b2b AS is_contract_b2b,
        r.city_name AS locale,
        c.guarantee,
        c.rental_administrator,
        cci.is_rental_paid_in_advance,
        REPLACE(REPLACE(ae.source_bill_item, 'entry.bill-item/', ''), '-', ' ') AS bill_item,
        'corretores robinhood' AS description,
        0 AS has_negotiation,
        0 AS has_installments,
        'monthly' AS purpose,
        'quinto andar' AS from_account_type,
        'ciq' AS to_account_type,
        'ciq' AS account_type,
        'payable' AS account_classification,
        pr.status AS status,
        'robinhood' AS paid_via,
        1.00000 * ae.due_amount AS due_amount,
        1.00000 * ae.due_amount AS invoice_due_amount,
        ae.accrual_year_month AS accrual_year_month,
        ae.accrual_year_month AS entry_accrual_year_month,
        ae.accrual_year_month AS entry_creation_accrual_year_month,
        DATE(ae.ts_created) AS entry_created_date,
        DATE(ae.ts_created) AS invoice_created_date,
        DATE(pr.dt_due) AS invoice_due_date,
        DATE(pr.dt_paid) AS invoice_paid_date,
        CAST(NULL AS STRING) AS invoice_canceled_date,
        c.contract_start,
        c.contract_annulment,
        CASE WHEN c.contract_start <= c.contract_annulment THEN false ELSE true END AS ended_before_started,
        c.status AS contract_status,
        aes.source_name AS type,
        rr.reason AS reason,
        rr.ts_created AS ts_created
    FROM
        datalake_robin_hood.accounting_entry AS ae
    INNER JOIN
        datalake_robin_hood_clean.accounting_entry_source AS aes
            ON aes.id = ae.id_source
    LEFT JOIN
        datalake_robin_hood_clean.accounting_entry_balance AS eb
            ON eb.id_accounting_entry = ae.id
    LEFT JOIN
        datalake_robin_hood_clean.payment_request AS pr
            ON pr.id = eb.id_payment_request
    LEFT JOIN
        contract AS c
            ON c.sk_contract = TRY_CAST(COALESCE(ae.id_contract, regexp_replace(ae.description, '[^0-9]', '')) AS BIGINT)
    LEFT JOIN
        rh_contract_info AS cci
            ON cci.sk_contract = c.sk_contract
    LEFT JOIN
        dw_rent.fact_house_listings AS rf
            ON rf.sk_contract = c.sk_contract
    LEFT JOIN
        dw_public.dim_region AS r
            ON r.sk_region = rf.sk_region
    LEFT JOIN
        recon_removal AS rr
            ON rr.id_accounting_entry = ae.id
    WHERE
        aes.source_name IN (
            'Corretagem de aluguel',
            'Imobiliárias for rent',
            'Executivo For Rent',
            'CIQ Campanhas'
        )
)
SELECT DISTINCT
    id_accounting_entry,
    sk_contract,
    bill_item,
    description,
    due_amount,
    accrual_year_month,
    invoice_paid_date,
    status,
    type,
    entry_created_date,
    reason AS recon_removals_reason,
    ts_created AS ts_created_recon_removals,
    NOW() AS ts_snapshot,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    rh_all
