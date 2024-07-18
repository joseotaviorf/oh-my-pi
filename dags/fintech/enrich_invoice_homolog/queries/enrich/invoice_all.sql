WITH
    business_day_count AS (
        SELECT
            DATE_TRUNC('month', date) AS year_month,
            date AS business_day,
            ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', date) ORDER BY date) AS row_num
        FROM datalake_quintoandar.aux_date
        WHERE
            weekend = 'Weekday'
    ),
    third_business_day AS (
        SELECT
            year_month,
            business_day AS third_business_day
        FROM
            business_day_count
        WHERE
            row_num = 3
    ), house_b2b_portability AS ( -- TODO [ODS] Move to an enrich
        SELECT
            hl.id_house_listing
        FROM
            datalake_ebdb_listing.house_listing hl
        JOIN
            datalake_ebdb_clean.house h
                ON h.id = hl.id_house
        JOIN
            datalake_ebdb_listing.portability p
                ON p.id_house = hl.id_house AND p.is_owner_b2b
        WHERE
            p.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, NOW())
    ), contracts as (
        SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
            c.id AS id_contract,
            CAST(c.rent AS DECIMAL(14, 2)) AS rent,
            CAST(c.billing_day_of_month AS SMALLINT) AS day_month_due,
            c.guarantee_type AS guarantee,
            c.type,
            c.status,
            c.paying_condo AS condo_payer,
            c.responsible_for_condo AS condo_responsible,
            c.paying_iptu AS iptu_payer,
            c.responsible_for_iptu AS iptu_responsible,
            CAST(c.rental_guarantee_installment AS SMALLINT) AS rental_insurance_installments,
            CAST(c.rental_guarantee_value AS  DECIMAL(14, 2)) AS rental_insurance_value,
            CAST(c.home_insurance_installment AS SMALLINT) AS home_insurance_installments,
            CAST(c.home_insurance_value AS DECIMAL(14, 2)) AS home_insurance_value,
            CAST(c.fist_rent_comission_fee AS DECIMAL(14, 2)) AS first_rental_commission,
            CAST(c.monthly_administration_fee AS DECIMAL(5, 4)) AS monthly_administration_fee,
            CAST(c.condo_price AS DECIMAL(14, 2)) AS condo,
            CAST(c.iptu AS DECIMAL(14, 2)) AS iptu,
            CAST(c.tenant_service_fee AS DECIMAL(5, 2)) AS tenant_service_fee,
            c.signature_type,
            c.status_closing AS closing_status,
            c.cancellation_reason,
            c.contract_version AS version,
            (hp.id_house_listing IS NOT NULL) OR contract_b2b.is_b2b AS is_b2b,
            contract_b2b.b2b_type,
            contract_b2b.b2b_prime_type,
            c.is_ongoing_contract,
            c.is_tenant_service_fee_opt_out,
            c.dt_started AS dt_start,
            c.dt_entered AS dt_entrance,
            c.dt_contract_expected_end AS dt_intended_end,
            c.dt_termination AS dt_annulment,
            c.ts_created,
            c.ts_updated,
            c.ts_signed AS ts_signature,
            c.ts_minuta_approved AS ts_draft_approved,
            CAST(c.ts_canceled AS TIMESTAMP) as ts_canceled,
            c.ts_tenant_service_fee_opt_out,
            CAST(c.ts_analyst_annulment_input AS TIMESTAMP) as ts_analyst_annulment_input
        FROM
            datalake_ebdb_contract.contract c
        LEFT JOIN
            datalake_ebdb_contract.contract_b2b contract_b2b
                ON contract_b2b.id_contract = c.id
        LEFT JOIN
            datalake_ebdb_listing.house_listing hl
                ON  hl.id_house = c.id_house
                    AND c.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01') AND COALESCE(hl.ts_listing_version_end, NOW())
        LEFT JOIN
            house_b2b_portability hp
                ON hp.id_house_listing = hl.id_house_listing

    )

SELECT
    fie.id AS id_invoice_entry,
    fie.id_region,
    c.id_contract,
    c.rent,
    c.version,
    c.guarantee,
    ie.description,
    ie.entry_type AS bill_item,
    il.invoice_frequency AS frequency,
    COALESCE(il.payment_status, 'not-invoiceable') AS status,
    COALESCE(il.invoice_user, 'quinto-andar') AS invoice_account_type,
    CASE
        WHEN (ie.from_account_type = 'contract'
            AND ie.to_account_type <> 'contract') THEN (-1.0) * fie.brl_entry_due_amount
        ELSE 1.0 * fie.brl_entry_due_amount
    END AS sb_value,
    CASE
        WHEN (ie.from_account_type = 'contract'
            AND ie.to_account_type = 'tenant') THEN (-1.0) *    (CASE
                                                                    WHEN (ie.from_account_type = 'contract'
                                                                        AND ie.to_account_type <> 'contract') THEN (-1.0) * fie.brl_entry_due_amount
                                                                    ELSE 1.0 * fie.brl_entry_due_amount
                                                                END)
        WHEN (ie.from_account_type = 'contract'
            AND ie.to_account_type = 'landlord') THEN (-1.0) *  (CASE
                                                                    WHEN (ie.from_account_type = 'contract'
                                                                        AND ie.to_account_type <> 'contract') THEN (-1.0) * fie.brl_entry_due_amount
                                                                    ELSE 1.0 * fie.brl_entry_due_amount
                                                                END)
        ELSE 1.0 * (CASE
                        WHEN (ie.from_account_type = 'contract'
                            AND ie.to_account_type <> 'contract') THEN (-1.0) * fie.brl_entry_due_amount
                        ELSE 1.0 * fie.brl_entry_due_amount
                    END)
    END AS sign_value,
    c.is_b2b,
    CASE
        WHEN TO_DATE(CAST(fie.id_created_date AS STRING), 'yyyyMMdd') <= td.third_business_day THEN TRUE
        ELSE FALSE
    END AS is_created_before_third_business_day,
    td.third_business_day AS dt_third_business_day,
    TO_DATE(DATE_TRUNC('month',c.ts_signature), 'yyyy-MM-dd') AS dt_contract_month_signed,
    TO_DATE(DATE_TRUNC('month',c.dt_start), 'yyyy-MM-dd') AS dt_contract_month_started,
    CASE
        WHEN fie.id_paid_date = -1 THEN NULL
        ELSE TO_DATE(CAST(fie.id_paid_date AS STRING), 'yyyyMMdd')
    END AS dt_invoice_paid,
    ie.accrual_year_month,
    ADD_MONTHS(TO_DATE(CAST(ie.accrual_year_month AS STRING), 'yyyyMM'), 1) AS dt_next_accrual,
    COALESCE(i.ts_created, TO_DATE(CAST(fie.id_created_date AS STRING), 'yyyyMMdd')) AS ts_created,
    TO_DATE(CAST(fie.id_created_date AS STRING), 'yyyyMMdd') AS dt_created_for_filter
FROM
    datalake_invoice_homolog.invoice_entries fie
LEFT JOIN
    datalake_retsuko.invoice_entry ie
        ON fie.id = ie.id
LEFT JOIN
    datalake_retsuko.invoice_info il
        ON il.id_invoice = fie.id_invoice
LEFT JOIN
    datalake_retsuko.invoice i
        ON i.id_external = il.id_invoice
LEFT JOIN
    contracts c
        ON c.id_contract = fie.id_contract
LEFT JOIN
    third_business_day td
        ON ADD_MONTHS(TO_DATE(CAST(ie.accrual_year_month AS STRING), 'yyyyMM'), 1) = td.year_month
WHERE
    ie.from_account_type NOT IN ('quinto andar', 'contract expenses')
    AND il.payment_status <> 'canceled'
    AND TO_DATE(CAST(fie.id_created_date AS STRING), 'yyyyMMdd') <= td.third_business_day
