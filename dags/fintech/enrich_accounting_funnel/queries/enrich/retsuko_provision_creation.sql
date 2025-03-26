WITH not_write_off_invoice AS (
    SELECT DISTINCT
        id_external
    FROM 
        datalake_retsuko.invoice 
    WHERE 
        (is_write_off = FALSE OR is_write_off IS NULL)
),

invoice_entry_version AS (
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
                'entry.bill-item/lockin') THEN 'adm fee'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar') THEN 'brokerage quinto andar'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-partner-select') THEN 'brokerage select'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') AND LOWER(e.description) LIKE '%consultor imobiliário%' THEN 'brokerage ciq'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-third-party-real-estate') THEN 'brokerage partner'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-estate-agent') THEN 'brokerage agent'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v1' THEN 'BFI v1'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v2' THEN 'BFI v2'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') THEN 'BFI'
        END AS revenue_name,
        CASE
            WHEN e.bill_item IN (
                'entry.bill-item/adm-fee',
                'entry.bill-item/igpm-adm-fee',
                'entry.bill-item/ipca-adm-fee',
                'entry.bill-item/adjustment-agreement-adm-fee',
                'entry.bill-item/lockin') THEN '420021'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-quinto-andar') THEN '420022'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-partner-select') THEN '700010'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner') AND LOWER(e.description) LIKE '%consultor imobiliário%' THEN '700007'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-adm-partner', 'entry.bill-item/brokerage-third-party-real-estate') THEN '700011'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-estate-agent') THEN '700006'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v1' THEN '420022'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee') AND ie.version = 'v2' THEN '420023'
        END AS account_number,
        i.accrual_year_month,
        IF(e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND e.producer = 'early-termination-v2' AND e.accrual_year_month < CAST(REPLACE(LEFT(DATE(e.ts_created) + INTERVAL '1' MONTH, 7), '-', '') AS INTEGER), DATE(e.ts_created) + INTERVAL '1' MONTH, DATE(e.ts_created)) AS dt_source_trigger,
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
        invoice_entry_version ie
            ON e.id_external = ie.id_finance_entity
    WHERE
        e.description != 'Crédito - Parcelamento corretagem - QuintoAndar'
        AND (
                (
                    (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                      'adm-fee',
                      'igpm-adm-partner-adm-fee',
                      'ipca-adm-partner-adm-fee',
                      'brokerage-installment-fee',
                      'brokerage-quinto-andar',
                      'brokerage-partner-select',
                      'brokerage-adm-partner',
                      'brokerage-estate-agent',
                      'brokerage-third-party-real-estate',
                      'lockin',
                      'adjustment-agreement-adm-fee',
                      'igpm-adm-fee',
                      'ipca-adm-fee'
                      )
                    )
                )
            )
        AND ct.country_code = 'BR'
        AND DATE(e.ts_created) >= '2024-01-01'
        AND af.type IN ('contract', 'tenant','landlord')
        AND at.type IN ('contract', 'tenant','landlord')
),

sap_entity AS (
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
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
),

df AS (
    SELECT
        id_contract,
        id_invoice,
        id_entry,
        version,
        source_name,
        revenue_name,
        account_number,
        accrual_year_month,
        dt_source_trigger,
        source_amount,
        id_sap_gateway_feature,
        event,
        status
    FROM
        retsuko_provisao r
    LEFT JOIN
        sap_entity se
            ON r.id_entry = se.id_finance_entity AND se.event = 'new-accounting-entries'
),

sap_gateway AS (
    SELECT
        f.id_feature,
        hash,
        f.sync_sap_status,
        s.status as sync_sap_job_status
    FROM
        datalake_sap_gateway_clean.feature f
    LEFT JOIN
        datalake_sap_gateway_clean.sync_sap_job s
            ON f.id_feature = s.id_feature
    WHERE
        erp_solution IN ('S4')
        AND type = 'LCM'
),

sap AS (
    SELECT
        hash,
        account_number,
        debit_credit,
        DATE(dt_created) AS dt_sap_created,
        DATE(dt_reference) AS dt_sap_reference
    FROM
        datalake_accounting_funnel.ledger
    WHERE
        dt_reference >= DATE('2024-01-01')
        AND (
            account_number IN ('420001', '420022', '420006', '420023', '420004', '420002', '420021', '420009', '420035', '420010', '420034', '420007', '430029', '420032', '420005', '420037', '420013', '420036', '430000', '413010', '410000', '430014', '413012', '420016', '430024', '430030', '430025', '430026', '420026', '420033', '430023', '430005', '413011', '420040')
            OR account_number IN ('700004', '700012', '700007', '700005', '700006', '700011', '700008', '700013', '700009', '700010', '700014', '700016', '700015')
        )
        --AND  transaction_type = 'SA'
),

df_final AS (
    SELECT
        id_contract,
        id_invoice,
        id_entry,
        version,
        source_name,
        revenue_name,
        accrual_year_month,
        CASE
          WHEN sap.hash IS NOT NULL THEN 'SUCCESS'
          WHEN sap.hash IS NULL AND sap_gateway.id_feature IS NOT NULL THEN 'SG FAILURE'
          WHEN sap.hash IS NULL AND sap_gateway.id_feature IS NULL THEN 'SB FAILURE'
        END AS status,
        IF(sap.hash IS NULL OR sap_gateway.id_feature IS NULL, FALSE, TRUE) AS is_completeness_compliance,
        source_amount,
        df.account_number,
        debit_credit AS sap_amount,
        dt_source_trigger,
        dt_sap_created,
        dt_sap_reference
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
),

metrics AS (
    SELECT
        'JE'||'-'||id_entry||'-'||'1'||'-'||'2'||'-'||
        CASE
            WHEN revenue_name = 'adm fee' THEN '1'
            WHEN revenue_name = 'brokerage quinto andar' THEN '2'
            WHEN revenue_name = 'service fee' THEN '3'
            WHEN revenue_name = 'BFI' THEN '4'
            WHEN revenue_name = 'BFI v1' THEN '4'
            WHEN revenue_name = 'BFI v2' THEN '4'
            WHEN revenue_name = 'brokerage select' THEN '5'
            WHEN revenue_name = 'brokerage ciq' THEN '5'
            WHEN revenue_name = 'brokerage partner' THEN '5'
            WHEN revenue_name = 'brokerage agent' THEN '5'
        END AS id_retsuko_provision_creation,
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
        IF(ABS(source_amount) - ABS(sap_amount) = 0 OR (source_amount = 0 AND sap_amount IS NULL), TRUE, FALSE) AS is_correctness_compliance,
        IF(dt_sap_reference BETWEEN dt_source_trigger AND DATE_ADD(dt_source_trigger, 3), TRUE, FALSE) AS is_temporality_compliance,
        dt_source_trigger,
        dt_sap_created,
        dt_sap_reference
    FROM
        df_final
)

SELECT
    id_retsuko_provision_creation,
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
    metrics
INNER JOIN
    not_write_off_invoice
        ON metrics.id_finance_entity = not_write_off_invoice.id_external
