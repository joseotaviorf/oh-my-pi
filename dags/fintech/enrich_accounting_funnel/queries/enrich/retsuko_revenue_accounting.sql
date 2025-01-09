WITH sap_entity AS (
    SELECT
        id_finance_entity,
        id_sap_gateway_feature,
        version,
        event,
        status
    FROM
        datalake_retsuko_clean.sap_entity
    WHERE
        id_finance_entity IS NOT NULL
        AND id_sap_gateway_feature IS NOT NULL
        AND event IN ('new-accounting-entries', 'payment-accounting-entries')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
),

retsuko AS (
    SELECT DISTINCT
        ct.id_external AS id_contract,
        i.id_external AS id_invoice,
        e.id_external AS id_entry,
        se.version,
        se.id_sap_gateway_feature,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item IN ('entry.bill-item/rental-anticipation-fee') THEN '420019'
            WHEN e.bill_item IN ('entry.bill-item/property-damage-fine') THEN '420003'
            --WHEN e.bill_item IN ('entry.bill-item/pro-guarantor-5A-installment') THEN '211415'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select',
            'entry.bill-item/brokerage-estate-agent', 'entry.bill-item/brokerage-third-party-real-estate') THEN '700005'
            WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN '700009'
        END AS revenue_account,
        CASE
            WHEN e.bill_item IN ('entry.bill-item/rental-anticipation-fee') THEN 'rental anticipation fee'
            WHEN e.bill_item IN ('entry.bill-item/property-damage-fine') THEN 'property damage fine'
            --WHEN e.bill_item IN ('entry.bill-item/pro-guarantor-5A-installment') THEN 'pro guarantor 5A installment'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-partner-select',
            'entry.bill-item/brokerage-estate-agent', 'entry.bill-item/brokerage-third-party-real-estate') THEN 'brokerage partners'
            WHEN e.bill_item IN ('entry.bill-item/adm-fee-adm-partner') THEN 'adm fee partner'
        END AS revenue_name,
        i.accrual_year_month,
        DATE(e.ts_created) AS dt_source_trigger,
        CAST(amount AS DECIMAL(12,2)) AS source_amount
    FROM
        datalake_retsuko.entry  e
    INNER JOIN
        datalake_retsuko_clean.account AS af
            ON e.id_from_account = af.id
    INNER JOIN
        datalake_retsuko_clean.account AS at
            ON e.id_to_account = at.id
    LEFT JOIN
        datalake_retsuko.invoice i
            ON e.id_invoice = i.id
    LEFT JOIN
        datalake_retsuko.invoice_info ii
            ON ii.id_invoice = i.id_external
    LEFT JOIN
        datalake_retsuko_clean.contract ct
            ON ct.id = e.id_contract
    LEFT JOIN
        sap_entity se
            ON e.id_external = se.id_finance_entity
    WHERE
        TRUE
        AND SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                      'rental-anticipation-fee',
                      'property-damage-fine',
                      'pro-guarantor-5A-installment',
                      'brokerage-adm-partner',
                      'brokerage-partner-select',
                      'brokerage-estate-agent',
                      'brokerage-third-party-real-estate',
                      'adm-fee-adm-partner'
                      )
        AND ct.country_code = 'BR'
        AND DATE(e.ts_created) >= '2024-01-01'
        AND af.type IN ('contract', 'tenant','landlord')
        AND at.type IN ('contract', 'tenant','landlord')
),

retsuko_fine AS (
    SELECT DISTINCT
        ct.id_external AS id_contract,
        i.id_external AS id_invoice,
        CAST(NULL AS INT) AS id_entry,
        se.version,
        se.id_sap_gateway_feature,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item IN ('entry.bill-item/fine-and-interest') THEN '420003'
            WHEN e.bill_item IN ('entry.bill-item/negotiation-fine-and-interest') THEN '420025'
            WHEN e.bill_item IN ('entry.bill-item/credit-card-revenue') THEN '420020'
            WHEN e.bill_item IN ('entry.bill-item/fine') THEN '420003'
            WHEN e.bill_item IN ('entry.bill-item/interest') THEN '611012'
        END AS revenue_account,
        CASE
            WHEN e.bill_item IN ('entry.bill-item/fine-and-interest') THEN 'fine and interest'
            WHEN e.bill_item IN ('entry.bill-item/negotiation-fine-and-interest') THEN 'negotiation fine and interest'
            WHEN e.bill_item IN ('entry.bill-item/credit-card-revenue') THEN 'credit card revenue'
            WHEN e.bill_item IN ('entry.bill-item/fine') THEN 'fine'
            WHEN e.bill_item IN ('entry.bill-item/interest') THEN 'interest'
        END AS revenue_name,
        i.accrual_year_month,
        DATE(i.ts_paid) AS dt_source_trigger,
        CAST(SUM(amount) AS DECIMAL(12,2)) AS source_amount
    FROM
        datalake_retsuko.entry  e
    INNER JOIN
        datalake_retsuko.invoice i
            ON e.id_invoice = i.id
    INNER JOIN
        datalake_retsuko.invoice_info ii
            ON ii.id_invoice = i.id_external
    INNER JOIN
        datalake_retsuko_clean.contract ct
            ON ct.id = i.id_contract
    LEFT JOIN
        sap_entity se
            ON i.id_external = se.id_finance_entity
    WHERE
        TRUE
        AND (
            (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                      'fine-and-interest',
                      'negotiation-fine-and-interest',
                      'fine',
                      'interest'
                      )) OR
            (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                      'credit-card-revenue'
                      ) AND (se.version = 'v2' OR se.version IS NULL))
            )
        AND ct.country_code = 'BR'
        AND i.ts_paid >= '2024-01-01'
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
    HAVING
        SUM(amount) != 0
),

retsuko_final AS (
    SELECT
        *
    FROM
        retsuko
    UNION ALL
    SELECT
        *
    FROM
        retsuko_fine
),

sap_gateway AS (
    SELECT
        f.id_finance_entity,
        f.id_feature,
        hash,
        f.sync_sap_status,
        s.status as sync_sap_job_status
    FROM
        datalake_sap_gateway.feature f
    LEFT JOIN
        datalake_sap_gateway.sync_sap_job s
            ON f.id_feature = s.id_feature
    WHERE
        erp_solution IN ('S4')
        AND type = 'LCM'
        AND status = 'done'
),

sap AS (
    SELECT
        id_finance_entity,
        hash,
        account_number,
        SUM(debit_credit) AS debit_credit,
        DATE(dt_created) AS dt_sap_created,
        DATE(dt_reference) AS dt_sap_reference
    FROM
        datalake_accounting_funnel.ledger
    WHERE

    WHERE
        dt_reference >= DATE('2024-01-01')
        AND account_number IN ('420019', '420003', '420025', '420020', '420003', '611012', '211415', '700005', '700009')
        --AND transaction_type = 'SA'
    GROUP BY 1, 2, 3, 5, 6
),

df AS (
    SELECT
        id_contract,
        id_invoice,
        id_entry,
        version,
        source_name,
        revenue_name,
        accrual_year_month,
        r.revenue_account AS account_number,
        MIN(CASE
          WHEN sap.hash IS NOT NULL THEN 'SUCCESS'
          WHEN sap.hash IS NULL AND sap_gateway.id_feature IS NOT NULL THEN 'SG FAILURE'
          WHEN sap.hash IS NULL AND sap_gateway.id_feature IS NULL THEN 'SB FAILURE'
        END) AS status,
        MIN(IF(sap.hash IS NULL OR sap_gateway.id_feature IS NULL, FALSE, TRUE)) AS is_completeness_compliance,
        CAST(source_amount AS DECIMAL(12,2)) AS source_amount,
        CAST(SUM(debit_credit) AS DECIMAL(12,2)) AS sap_amount,
        MAX(dt_source_trigger) AS dt_source_trigger,
        MAX(dt_sap_created) AS dt_sap_created,
        MAX(dt_sap_reference) AS dt_sap_reference
    FROM
        retsuko_final r
    LEFT JOIN
        sap_gateway
            ON r.id_sap_gateway_feature = sap_gateway.id_feature
    LEFT JOIN
        sap
            ON sap.hash = sap_gateway.hash AND r.revenue_account = sap.account_number
    GROUP BY 1, 2, 3, 4, 5 ,6 ,7 ,8 ,11
),

df_final AS (
    SELECT
        'JE'||'-'||IF(id_entry IS NOT NULL, id_entry, id_invoice)||'-'||'1'||'-'||'4'||'-'||
        CASE
          WHEN revenue_name = 'property damage fine' THEN '1'
          WHEN revenue_name = 'rental anticipation fee' THEN '2'
          WHEN revenue_name = 'fine and interest' THEN '3'
          WHEN revenue_name = 'negotiation fine and interest' THEN '4'
          WHEN revenue_name = 'credit card revenue' THEN '5'
          WHEN revenue_name = 'interest' THEN '6'
          WHEN revenue_name = 'fine' THEN '7'
          WHEN revenue_name = 'pro guarantor 5A installment' THEN '8'
          WHEN revenue_name = 'brokerage partners' THEN '9'
          WHEN revenue_name = 'adm fee partner' THEN '10'
        END AS id_retsuko_revenue_accounting,
        id_contract AS id_business_entity,
        id_invoice AS id_finance_entity,
        id_entry AS id_finance_entity_entry,
        version,
        source_name,
        revenue_name,
        accrual_year_month,
        status,
        source_amount,
        sap_amount,
        account_number,
        is_completeness_compliance,
        IF((ABS(source_amount) - ABS(sap_amount)) >= 0.05 OR (ABS(source_amount) - ABS(sap_amount)) <= -0.05 OR sap_amount IS NULL, FALSE, TRUE) AS is_correctness_compliance,
        IF(dt_sap_reference BETWEEN dt_source_trigger AND DATE_ADD(dt_source_trigger, 3), TRUE, FALSE) AS is_temporality_compliance,
        dt_source_trigger,
        dt_sap_created,
        dt_sap_reference
    FROM
        df
)
SELECT
    id_retsuko_revenue_accounting,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    source_name,
    revenue_name,
    accrual_year_month,
    status,
    source_amount,
    sap_amount,
    account_number,
    is_completeness_compliance,
    is_correctness_compliance,
    is_temporality_compliance,
    IF(is_completeness_compliance IS TRUE AND is_correctness_compliance IS TRUE AND is_temporality_compliance IS TRUE, TRUE, FALSE) AS is_compliance,
    dt_source_trigger,
    dt_sap_created,
    dt_sap_reference
FROM
    df_final
