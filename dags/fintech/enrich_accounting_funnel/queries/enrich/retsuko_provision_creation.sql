WITH invoice_entry_version AS (
    SELECT DISTINCT
        i.id_external AS id_finance_entity,
        s.version
    FROM  
        datalake_retsuko.invoice AS i
    LEFT JOIN datalake_retsuko_clean.sap_entity AS s 
        ON s.id_finance_entity = i.id_external
    WHERE 
        event NOT IN ('payment-accounting-entries')
        AND id_sap_gateway_feature IS NOT NULL
        AND id_finance_entity IS NOT NULL

    UNION ALL 
    
    SELECT DISTINCT
        e.id_external AS id_finance_entity,
        s.version
    FROM 
        datalake_retsuko.entry AS e
    LEFT JOIN datalake_retsuko_clean.sap_entity AS s 
        ON s.id_finance_entity = e.id_external
    WHERE 
        event NOT IN ('payment-accounting-entries')
        AND id_sap_gateway_feature IS NOT NULL
        AND id_finance_entity IS NOT NULL
),

retsuko_provisao AS (
    SELECT DISTINCT
        ct.id_external AS id_contract,
        i.id_external AS id_invoice,
        e.id_external AS id_entry,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item IN (
                'entry.bill-item/adm-fee', 
                'entry.bill-item/igpm-adm-fee', 
                'entry.bill-item/ipca-adm-fee', 
                'entry.bill-item/adjustment-agreement-adm-fee', 
                'entry.bill-item/lockin',
                'entry.bill-item/adm-fee-tax-pcc-adm-partner',
                'entry.bill-item/adm-fee-tax-pcc-quintoandar',
                'entry.bill-item/adm-fee-tax-ir-quinto-andar',
                'entry.bill-item/adm-fee-tax-ir',
                'entry.bill-item/adm-fee-tax-pcc',
                'entry.bill-item/adm-fee-tax-ir-adm-partner',
                'entry.bill-item/adm-fee-tax-pcc-quinto-andar') THEN 'adm fee'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar', 
                'entry.bill-item/brokerage-fee-tax-ir-adm-partner', 
                'entry.bill-item/brokerage-fee-tax-ir', 
                'entry.bill-item/brokerage-fee-tax-ir-quinto-andar') THEN 'brokerage'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v1' THEN 'brokerage installment fee v1'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v2' THEN 'brokerage installment fee v2'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') THEN 'brokerage installment fee'
        END AS revenue_name,
        CASE
            WHEN e.bill_item IN (
                'entry.bill-item/adm-fee', 
                'entry.bill-item/igpm-adm-fee', 
                'entry.bill-item/ipca-adm-fee', 
                'entry.bill-item/adjustment-agreement-adm-fee', 
                'entry.bill-item/lockin',
                'entry.bill-item/adm-fee-tax-pcc-adm-partner',
                'entry.bill-item/adm-fee-tax-pcc-quintoandar',
                'entry.bill-item/adm-fee-tax-ir-quinto-andar',
                'entry.bill-item/adm-fee-tax-ir',
                'entry.bill-item/adm-fee-tax-pcc',
                'entry.bill-item/adm-fee-tax-ir-adm-partner',
                'entry.bill-item/adm-fee-tax-pcc-quinto-andar') THEN '31101.02.02'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar', 
                'entry.bill-item/brokerage-fee-tax-ir-adm-partner', 
                'entry.bill-item/brokerage-fee-tax-ir', 
                'entry.bill-item/brokerage-fee-tax-ir-quinto-andar') THEN '31101.01.04'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v1' THEN '31101.01.04'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v2' THEN '31101.01.13'
        END AS account_number,
        i.accrual_year_month,
        DATE(i.ts_created) AS dt_source_provision_created,
        CAST(SUM(amount) AS DECIMAL(12,2)) AS source_provision_amount
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
        invoice_entry_version ie 
            ON i.id_external = ie.id_finance_entity
    WHERE 
        description != 'Crédito - Parcelamento corretagem - QuintoAndar' 
        AND (
                (
                    (ii.invoice_user = 'landlord') AND 
                    (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                      'adm-fee',  
                      'adm-fee-tax-pcc-adm-partner',
                      'adm-fee-tax-pcc-quintoandar',
                      'adm-fee-tax-ir-quinto-andar',
                      'adm-fee-tax-ir',
                      'adm-fee-tax-pcc',
                      'adm-fee-tax-ir-adm-partner',
                      'adm-fee-tax-pcc-quinto-andar',
                      'brokerage-installment-fee', 
                      'brokerage-quinto-andar',
                      'brokerage-fee-tax-ir-adm-partner',
                      'brokerage-fee-tax-ir',
                      'brokerage-fee-tax-ir-quinto-andar',
                      'lockin', 
                      'pro-guarantor-5A-installment', 
                      'adjustment-agreement-adm-fee', 
                      'igpm-adm-fee', 
                      'ipca-adm-fee'
                      )
                    ) 
                ) 
            )
        AND ct.country_code = 'BR'
        AND DATE(i.ts_created) >= '2024-01-01'
        AND i.status != 'canceled'
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
    HAVING 
        SUM(amount) != 0
),

retsuko_reversao AS (
    SELECT DISTINCT
        ct.id_external AS id_contract,
        i.id_external AS id_invoice,
        NULL AS id_entry,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item IN (
              'entry.bill-item/adm-fee', 
              'entry.bill-item/igpm-adm-fee', 
              'entry.bill-item/ipca-adm-fee', 
              'entry.bill-item/adjustment-agreement-adm-fee', 
              'entry.bill-item/lockin',
              'entry.bill-item/adm-fee-tax-pcc-adm-partner',
              'entry.bill-item/adm-fee-tax-pcc-quintoandar',
              'entry.bill-item/adm-fee-tax-ir-quinto-andar',
              'entry.bill-item/adm-fee-tax-ir',
              'entry.bill-item/adm-fee-tax-pcc',
              'entry.bill-item/adm-fee-tax-ir-adm-partner',
              'entry.bill-item/adm-fee-tax-pcc-quinto-andar') THEN 'adm fee'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar',
              'entry.bill-item/brokerage-fee-tax-ir-adm-partner', 
              'entry.bill-item/brokerage-fee-tax-ir', 
              'entry.bill-item/brokerage-fee-tax-ir-quinto-andar', 
              'entry.bill-item/brokerage-installment') THEN 'brokerage'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v1' THEN 'brokerage installment fee v1'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v2' THEN 'brokerage installment fee v2'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') THEN 'brokerage installment fee'
            WHEN e.bill_item = 'entry.bill-item/brokerage-quinto-andar-postponed' AND ie.version = 'v1' THEN 'brokerage'
        END AS revenue_name,
        CASE
            WHEN e.bill_item IN (
              'entry.bill-item/adm-fee', 
              'entry.bill-item/igpm-adm-fee', 
              'entry.bill-item/ipca-adm-fee', 
              'entry.bill-item/adjustment-agreement-adm-fee', 
              'entry.bill-item/lockin',
              'entry.bill-item/adm-fee-tax-pcc-adm-partner',
              'entry.bill-item/adm-fee-tax-pcc-quintoandar',
              'entry.bill-item/adm-fee-tax-ir-quinto-andar',
              'entry.bill-item/adm-fee-tax-ir',
              'entry.bill-item/adm-fee-tax-pcc',
              'entry.bill-item/adm-fee-tax-ir-adm-partner',
              'entry.bill-item/adm-fee-tax-pcc-quinto-andar') THEN '31101.02.02'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar',
              'entry.bill-item/brokerage-fee-tax-ir-adm-partner', 
              'entry.bill-item/brokerage-fee-tax-ir', 
              'entry.bill-item/brokerage-fee-tax-ir-quinto-andar', 
              'entry.bill-item/brokerage-installment') THEN '31101.01.04'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v1' THEN '31101.01.04'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v2' THEN '31101.01.13'
            WHEN e.bill_item = 'entry.bill-item/brokerage-quinto-andar-postponed' AND ie.version = 'v1' THEN '31101.01.04'
        END AS account_number,
        i.accrual_year_month,
        DATE(i.ts_paid) AS dt_source_reversion_created,
        CAST(SUM(amount) AS DECIMAL(12,2)) AS source_reversion_amount
    FROM 
        datalake_retsuko.entry e
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
        invoice_entry_version ie 
            ON i.id_external = ie.id_finance_entity
    WHERE 
        description != 'Crédito - Parcelamento corretagem - QuintoAndar' 
        AND (
                (
                    (ii.invoice_user = 'landlord') AND 
                    (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                      'adm-fee',  
                      'adm-fee-tax-pcc-adm-partner',
                      'adm-fee-tax-pcc-quintoandar',
                      'adm-fee-tax-ir-quinto-andar',
                      'adm-fee-tax-ir',
                      'adm-fee-tax-pcc',
                      'adm-fee-tax-ir-adm-partner',
                      'adm-fee-tax-pcc-quinto-andar',
                      'brokerage-installment-fee', 
                      'brokerage-quinto-andar',
                      'brokerage-fee-tax-ir-adm-partner',
                      'brokerage-fee-tax-ir',
                      'brokerage-fee-tax-ir-quinto-andar',
                      'lockin', 
                      'pro-guarantor-5A-installment', 
                      'adjustment-agreement-adm-fee', 
                      'igpm-adm-fee', 
                      'ipca-adm-fee'
                      )
                    ) 
                ) 
            OR (e.bill_item = 'entry.bill-item/brokerage-quinto-andar-postponed' AND ie.version = 'v1'))
        AND ct.country_code = 'BR'
        AND DATE(i.ts_created) >= '2024-01-01'
        AND i.status != 'canceled'
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
    HAVING 
        SUM(amount) != 0
),

sap_entity AS (
    SELECT
        id_finance_entity,
        id_sap_gateway_feature,
        event,
        status
    FROM 
        datalake_retsuko_clean.sap_entity
    WHERE 
        id_finance_entity IS NOT NULL
        AND id_sap_gateway_feature IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
),

df AS (
    SELECT
        id_contract,
        id_invoice,
        id_entry,
        source_name,
        revenue_name,
        account_number,
        accrual_year_month,
        dt_source_provision_created,
        NULL AS dt_source_reversion_created,
        source_provision_amount,
        0 AS source_reversion_amount,
        id_sap_gateway_feature,
        event,
        status
    FROM 
        retsuko_provisao r 
    LEFT JOIN
        sap_entity se 
            ON r.id_entry = se.id_finance_entity AND se.event = 'new-accounting-entries'

    UNION ALL

    SELECT
        id_contract,
        id_invoice,
        id_entry,
        source_name,
        revenue_name,
        account_number,
        accrual_year_month,
        NULL AS dt_source_provision_created,
        dt_source_reversion_created,
        0 AS source_provision_amount,
        source_reversion_amount,
        id_sap_gateway_feature,
        event,
        status
    FROM 
        retsuko_reversao r 
    LEFT JOIN
        sap_entity se 
            ON r.id_invoice = se.id_finance_entity AND se.event = 'clearing-accounting-entries'
),

sap_gateway AS (
    SELECT 
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
        erp_solution = 'B1'
        AND type = 'LCM'
),

sap AS (
    SELECT 
        hash,
        account_number,
        account_number,
        SUM(debit_credit) AS debit_credit,
        DATE(dt_created) AS dt_sap_created,
        DATE(dt_reference) AS dt_sap_reference
    FROM 
        datalake_accounting_funnel.ledger
    WHERE 
        account_number like '31101%'
        AND document_number like 'JE %'
    GROUP BY 1, 2, 3, 5, 6
),

df_final AS (
    SELECT 
        id_contract,
        id_invoice,
        source_name,
        revenue_name,
        accrual_year_month,
        MIN(CASE 
          WHEN sap.hash IS NOT NULL THEN 'SUCCESS'
          WHEN sap.hash IS NULL AND sap_gateway.id_feature IS NOT NULL THEN 'SG FAILURE'
          WHEN sap.hash IS NULL AND sap_gateway.id_feature IS NULL THEN 'SB FAILURE'
        END) AS status,
        MIN(IF(sap.hash IS NULL OR sap_gateway.id_feature IS NULL, FALSE, TRUE)) AS is_completeness_compliance,
        CAST(SUM(source_provision_amount) AS DECIMAL(12,2)) AS source_provision_amount,
        CAST(SUM(CASE WHEN event = 'new-accounting-entries' THEN debit_credit END) AS DECIMAL(12,2)) AS sap_provision_amount,
        CAST(SUM(source_reversion_amount) AS DECIMAL(12,2)) AS source_reversion_amount,
        CAST(SUM(CASE WHEN event = 'clearing-accounting-entries' THEN debit_credit END) AS DECIMAL(12,2)) AS sap_reversion_amount,
        MAX(dt_source_provision_created) AS dt_source_provision_created,
        MAX(dt_source_reversion_created) AS dt_source_reversion_created,
        MAX(CASE WHEN event = 'new-accounting-entries' THEN dt_sap_created END) AS dt_sap_provision_created,
        MAX(CASE WHEN event = 'clearing-accounting-entries' THEN dt_sap_created END) AS dt_sap_reversion_created
    FROM 
        df
    LEFT JOIN
        sap_gateway
            ON df.id_sap_gateway_feature = sap_gateway.id_feature
    LEFT JOIN
        sap 
            ON sap.hash = sap_gateway.hash 
            AND df.account_number = sap.account_number
    WHERE 
        TRUE
    GROUP BY 1, 2, 3, 4, 5
),

metrics AS (
    SELECT
        'JE'||'-'||id_invoice||'-'||'1'||'-'|| 
        CASE
            WHEN revenue_name = 'adm fee' THEN '1'
            WHEN revenue_name = 'brokerage' THEN '2' 
            WHEN revenue_name = 'service fee' THEN '3'
            WHEN revenue_name = 'brokerage installment fee' THEN '4'
            WHEN revenue_name = 'brokerage installment fee v1' THEN '4' 
            WHEN revenue_name = 'brokerage installment fee v2' THEN '4'
        END AS id_retsuko_provision_creation,
        id_contract AS id_business_entity,
        id_invoice AS id_finance_entity,
        source_name,
        revenue_name,
        accrual_year_month,
        status,
        source_provision_amount,
        sap_provision_amount,
        source_reversion_amount,
        sap_reversion_amount,
        is_completeness_compliance,
        IF(source_provision_amount + sap_provision_amount = 0 OR (source_provision_amount = 0 AND sap_provision_amount IS NULL), true, false) AS is_provision_correctness_compliance,
        IF((source_reversion_amount - sap_reversion_amount = 0) OR (source_reversion_amount = 0 AND sap_reversion_amount IS NULL) OR (dt_source_reversion_created IS NULL), true, false) AS is_reversion_correctness_compliance,
        IF(dt_sap_provision_created <= date_add(dt_source_provision_created, 7), true, false) AS is_provision_temporality_compliance,
        IF((dt_sap_reversion_created <= date_add(dt_source_reversion_created, 7)) OR (dt_source_reversion_created IS NULL), true, false) AS is_reversion_temporality_compliance,
        dt_source_provision_created,
        dt_sap_provision_created,
        dt_source_reversion_created,
        dt_sap_reversion_created
    FROM 
        df_final
)

SELECT
    id_retsuko_provision_creation,
    id_business_entity,
    id_finance_entity,
    source_name,
    revenue_name,
    accrual_year_month,
    status,
    source_provision_amount,
    sap_provision_amount,
    source_reversion_amount,
    sap_reversion_amount,
    is_completeness_compliance,
    is_provision_correctness_compliance,
    is_reversion_correctness_compliance,
    is_provision_temporality_compliance,
    is_reversion_temporality_compliance,
    IF(is_provision_correctness_compliance = TRUE AND is_reversion_correctness_compliance = TRUE, TRUE, FALSE) AS is_correctness_compliance,
    IF(is_provision_temporality_compliance = TRUE AND is_reversion_temporality_compliance = TRUE, TRUE, FALSE) AS is_temporality_compliance,
    IF(is_provision_correctness_compliance = TRUE AND is_reversion_correctness_compliance = TRUE AND is_provision_temporality_compliance = TRUE AND is_reversion_temporality_compliance = TRUE, TRUE, FALSE) AS is_compliance,
    dt_source_provision_created,
    dt_sap_provision_created,
    dt_source_reversion_created,
    dt_sap_reversion_created
FROM
    metrics