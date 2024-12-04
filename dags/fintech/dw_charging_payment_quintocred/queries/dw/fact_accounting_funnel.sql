WITH
propose AS (
    SELECT
        id,
        billing_model
    FROM
        datalake_rental_guarantee_platform_clean.propose
),
direct_billing AS (
    SELECT
        e.propose AS id_business_entity,
        br.dt_due,
        br.status AS payment_status,
        cast( br.id AS VARCHAR(10) ) AS id_finance_entity,
        e.amount AS source_amount
    FROM
        datalake_rental_guarantee_platform_clean.billing_report br
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.entry e
        ON br.id = e.id_billing_report
    LEFT JOIN
        propose p
        ON e.propose = p.id
    WHERE
        p.billing_model = 'BROKER'
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY e.propose , br.dt_due
            ORDER BY br.ts_updated DESC
        ) = 1
),
payment_no_ws AS (
    SELECT
        CAST( p.id AS VARCHAR(10) ) AS id_finance_entity,
        p.id_propose AS id_business_entity,
        'rental guarantee platform' AS source_name,
        p.gateway,
        p.billing_type,
        p.status AS payment_status,
        COALESCE( DATE( p.ts_due ), DATE( p.ts_created ) ) as due_date,
        p.value AS source_amount,
        p.product_type AS revenue_name
    FROM
        datalake_rental_guarantee_platform_clean.payment p
    LEFT JOIN propose pp
        ON p.id_propose = pp.id
    WHERE
    ( p.gateway != 'WALLSTREET' OR p.billing_type = 'ANNUAL_CREDIT_CARD')
    AND p.product_type IN ( 'GUARANTEE', 'ACTIVATION')
),
payment_ws AS (
    SELECT
        COALESCE( p.unicid, CAST( p.id AS VARCHAR(10) ) ) AS id_finance_entity,
        p.id_propose AS id_business_entity,
        'rental guarantee platform' AS source_name,
        gateway,
        billing_type,
        p.status AS payment_status,
        ts_due AS due_date,
        p.value AS source_amount,
        p.product_type AS revenue_name
    FROM
        datalake_rental_guarantee_platform_clean.payment p
    LEFT JOIN
        propose pp ON p.id_propose = pp.id
    WHERE
    p.gateway = 'WALLSTREET'
    AND p.product_type IN ('GUARANTEE', 'ACTIVATION')
    AND p.billing_type <> 'ANNUAL_CREDIT_CARD'
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY p.id_propose, date_trunc( 'MONTH', DATE( p.ts_due ) )
            ORDER BY p.ts_updated DESC
        ) = 1
    ),
recurrency_delinquency AS (
    SELECT
        *
    FROM
        datalake_rental_guarantee_platform_clean.delinquency
    WHERE
        id_type IN (0,4)
),
sap_feature AS (
    SELECT
        f.id_feature,
        f.id_business_entity,
        f.id_finance_entity,
        f.id_source,
        f.sync_sap_status AS feature_sync_status,
        f.request_payload,
        ssj.sap_payload,
        ssj.status AS sync_sap_status,
        DATE( ssj.ts_synced ) AS dt_sync,
        hash,
        ssj.type
    FROM
        datalake_sap_gateway_clean.sync_sap_job ssj
    LEFT JOIN
        datalake_sap_gateway_clean.feature f
        ON f.id_feature = ssj.id_feature
    WHERE
    f.source = 'rental-guarantee-platform'
    AND ssj.status = 'done'
    AND ssj.type = 'NF'
),
sap_ledger AS (
    SELECT
        *
    FROM
        datalake_accounting_funnel.ledger
    WHERE
        account_number IN ('31101.07.07', '31102.01.02')
        OR account_number IN ('420016', '420003')
),
accounting_funnel_no_ws AS (
    SELECT
        pnws.id_business_entity,
        pnws.id_finance_entity,
        CAST( NULL AS VARCHAR(20) ) AS id_finance_entity_entry,
        sf.hash,
        l.id_document,
        pnws.source_name,
        'revenue accounting' AS accounting_type,
        'Serviços Prestados - Velo' AS accounting_name,
        sf.sync_sap_status AS status,
        pnws.billing_type AS source_billing_type,
        pnws.payment_status AS source_payment_status,
        pnws.source_amount,
        l.debit_credit AS sap_amount,
        date_trunc('month',due_date) AS accrual_year_month,
        l.accrual_year_month AS accrual_year_month_sap,
        pnws.due_date AS dt_source_trigger,
        l.dt_reference AS dt_sap_reference,
        l.dt_created AS dt_sap_created
    FROM
        payment_no_ws pnws
    LEFT JOIN
        sap_feature sf
        ON  CAST( pnws.id_business_entity AS VARCHAR(10) ) = sf.id_business_entity
        AND CAST( pnws.id_finance_entity  AS VARCHAR(10) ) = sf.id_finance_entity
    LEFT JOIN sap_ledger l
        ON  sf.hash = l.hash
        AND l.account_number IN ('31101.07.07', '420016')
),
accounting_funnel_ws AS (
    SELECT
        pws.id_business_entity,
        pws.id_finance_entity,
        CAST( NULL AS VARCHAR(20) ) AS id_finance_entity_entry,
        sf.hash,
        l.id_document,
        pws.source_name,
        'revenue accounting' AS accounting_type,
        'Serviços Prestados - Velo' AS accounting_name,
        sf.sync_sap_status AS status,
        pws.billing_type AS source_billing_type,
        pws.payment_status AS source_payment_status,
        pws.source_amount,
        l.debit_credit AS sap_amount,
        date_trunc('month',pws.due_date) AS accrual_year_month,
        l.accrual_year_month AS accrual_year_month_sap,
        pws.due_date AS dt_source_trigger,
        l.dt_reference AS dt_sap_reference,
        l.dt_created AS dt_sap_created
    FROM
        payment_ws pws
    LEFT JOIN sap_feature sf
        ON  CAST(pws.id_business_entity AS VARCHAR(10)) = sf.id_business_entity
        AND CAST(pws.id_finance_entity  AS VARCHAR(10)) = sf.id_finance_entity
    LEFT JOIN sap_ledger l
        ON  sf.hash = l.hash
        AND l.account_number IN ('31101.07.07', '420016')
),
accounting_funnel_billing AS (
    SELECT
        db.id_business_entity,
        db.id_finance_entity,
        CAST( NULL AS VARCHAR(20) ) AS id_finance_entity_entry,
        sf.hash,
        l.id_document,
        'rental guarantee platform - billing' AS source_name,
        'revenue accounting' AS accounting_type,
        'Serviços Prestados - Velo' AS accounting_name,
        sf.sync_sap_status AS status,
        'Billing Direto' AS source_billing_type,
        db.payment_status AS source_payment_status,
        db.source_amount,
        l.debit_credit AS sap_amount,
        date_trunc( 'MONTH', db.dt_due)  AS accrual_year_month,
        l.accrual_year_month AS accrual_year_month_sap,
        db.dt_due AS dt_source_trigger,
        l.dt_reference AS dt_sap_reference,
        l.dt_created AS dt_sap_created
    FROM
        direct_billing db
    LEFT JOIN
        sap_feature sf
        ON  CAST(db.id_business_entity AS VARCHAR(10)) = sf.id_business_entity
        AND CAST(db.id_finance_entity  AS VARCHAR(10)) = sf.id_finance_entity
    LEFT JOIN
        sap_ledger l
        ON sf.hash = l.hash
        AND l.account_number IN ('31101.07.07', '420016')
),
accounting_funnel_wo_payment AS (
    SELECT DISTINCT
        sf.id_business_entity,
        sf.id_finance_entity,
        '' AS id_finance_entity_entry,
        sf.hash,
        l.id_document,
        'rental guarantee platform - billing' AS source_name,
        'revenue accounting' AS accounting_type,
        'Serviços Prestados - Velo' AS accounting_name,
        sf.sync_sap_status AS status,
        '' AS source_billing_type,
        '' AS source_payment_status,
        '' AS source_amount,
        l.debit_credit AS sap_amount,
        date(concat(LEFT(l.accrual_year_month,4),'-',RIGHT(l.accrual_year_month,2),'-',01)) AS accrual_year_month,
        l.accrual_year_month AS accrual_year_month_sap,
        '' AS dt_source_trigger,
        l.dt_reference AS dt_sap_reference,
        l.dt_created AS dt_sap_created
    FROM sap_feature sf
    LEFT JOIN sap_ledger l
        ON sf.hash = l.hash
        AND l.account_number IN ('31101.07.07', '420016')
),
accounting_funnel_qc AS (
    SELECT
        *
    FROM
        accounting_funnel_billing

    UNION

    SELECT
        *
    FROM
        accounting_funnel_no_ws

    UNION

    SELECT
        *
    FROM
        accounting_funnel_ws
),
accounting_funnel_wo_payment_missing AS (
    SELECT
        b.*
    FROM
        accounting_funnel_qc a
    RIGHT JOIN
        accounting_funnel_wo_payment b
        ON CONCAT( a.id_business_entity, DATE( a.accrual_year_month ) ) = concat( b.id_business_entity, b.accrual_year_month )
    WHERE CONCAT( a.id_business_entity, DATE( a.accrual_year_month ) ) IS NULL
),
accounting_funnel_qc_final AS (
    SELECT
        *
    FROM
        accounting_funnel_qc
    UNION
    SELECT
        *
    FROM
        accounting_funnel_wo_payment_missing
)
SELECT
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    hash,
    id_document,
    source_name,
    accounting_type,
    accounting_name,
    status,
    source_billing_type,
    source_payment_status,
    ROW_NUMBER() OVER(
        PARTITION BY id_business_entity, accrual_year_month
        ORDER BY hash ASC NULLS LAST
    ) AS rn_nf,
    source_amount,
    sap_amount,
    accrual_year_month,
    accrual_year_month_sap,
    dt_source_trigger,
    dt_sap_reference,
    dt_sap_created
FROM
    accounting_funnel_qc_final
