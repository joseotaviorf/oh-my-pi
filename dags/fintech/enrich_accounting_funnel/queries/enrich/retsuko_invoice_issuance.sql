WITH grouped_adm_fee AS (
    SELECT
        e.id_invoice,
        e.ts_created,
        e.bill_item,
        e.amount,
        e.description,
        e.producer,
        IF(bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin'), 'adm-fee', bill_item) AS bill_item_grouped
    FROM
        datalake_retsuko.entry e
    INNER JOIN
        datalake_retsuko.invoice i
            ON e.id_invoice = i.id
    WHERE
        description != 'Crédito - Parcelamento corretagem - QuintoAndar'
),

treated_entry AS (
    SELECT
        e.id_invoice,
        e.ts_created,
        e.bill_item,
        e.description,
        e.producer,
        e.amount,
        SUM(amount) OVER (partition by i.id_external, e.bill_item_grouped) as agg
    FROM
        grouped_adm_fee e
    INNER JOIN
        datalake_retsuko.invoice i
            ON e.id_invoice = i.id
),

contract_type AS (
    SELECT
        ct.id_external AS id_contract,
        i.id_external AS id_invoice,
        e.id_external AS id_entry,
        IF(LENGTH(ca.cpf) = 18, 'PJ', 'PF') AS contract_type
    FROM
        datalake_retsuko.entry AS e
    INNER JOIN
        datalake_retsuko_clean.contract AS ct
            ON e.id_contract = ct.id
    LEFT JOIN
        datalake_retsuko.invoice AS i
            ON e.id_invoice = i.id
    LEFT JOIN
        datalake_ebdb_clean.contract_person_aud AS ca
            ON ct.id_external = ca.id_contract
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS ur
            ON ca.rev = ur.id
    WHERE
        DATE(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0))) <= DATE(e.ts_created)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ca.id_contract, e.id_external ORDER BY rev DESC) = 1
),

retsuko_pre AS (
    SELECT DISTINCT
        ct.id_external AS id_business_entity,
        ctt.contract_type,
        i.id_external AS id_finance_entity,
        CAST(NULL AS INT) AS id_finance_entity_entry,
        i.id_external AS id_entity,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') THEN 'adm fee'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee', 'entry.bill-item/brokerage-quinto-andar') THEN 'brokerage quinto andar'
        END AS revenue_name,
        i.accrual_year_month,
        DATE(i.ts_due) AS dt_source_trigger,
        CAST(SUM(amount) AS DECIMAL(12,2)) AS source_amount
    FROM
        treated_entry e
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
        contract_type ctt
            ON ctt.id_invoice = i.id_external
    WHERE
        description != 'Crédito - Parcelamento corretagem - QuintoAndar'
    AND agg > 0
    AND (
            (
                (ii.invoice_user = 'landlord') AND
                (NOT(i.ts_due > current_date AND i.accrual_year_month < 202405)) AND
                (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                  'adm-fee',
                  'brokerage-installment-fee',
                  'brokerage-quinto-andar',
                  'lockin',
                  'adjustment-agreement-adm-fee',
                  'igpm-adm-fee',
                  'ipca-adm-fee'
                  )
                )
            )
        )
    AND ct.country_code = 'BR'
    AND ii.invoice_frequency != 'extra'
    AND i.status != 'canceled'
    AND DATE(i.ts_created) >= '2024-01-01'
    AND NOT(ctt.contract_type = 'PF' AND e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin'))
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9
    HAVING
        SUM(amount) != 0
),

retsuko_pos AS (
    SELECT DISTINCT
        ct.id_external AS id_business_entity,
        ctt.contract_type,
        i.id_external AS id_finance_entity,
        e.id_external AS id_finance_entity_entry,
        e.id_external AS id_entity,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item = 'entry.bill-item/service-fee' THEN 'service fee'
            WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') THEN 'adm fee'
        END AS revenue_name,
        e.accrual_year_month,
        MIN(CASE
          WHEN e.bill_item = 'entry.bill-item/service-fee' AND e.accrual_year_month < 202405 THEN DATE(i.ts_paid)
          WHEN e.bill_item = 'entry.bill-item/service-fee' AND e.accrual_year_month >= 202405 AND ct.guarantee = 'contract.guarantee/fairfax' AND e.producer NOT IN ('onboarding-routine', 'onboarding-routine-delayed') THEN TO_DATE(CONCAT(e.accrual_year_month, '01'), 'yyyyMMdd') + INTERVAL '1' MONTH
          WHEN e.bill_item = 'entry.bill-item/service-fee' AND e.accrual_year_month >= 202405 THEN TO_DATE(CONCAT(e.accrual_year_month, '01'), 'yyyyMMdd')
          ELSE DATE(e.ts_created)
        END) AS dt_source_trigger,
        CAST(SUM(amount) AS DECIMAL(12,2)) AS source_amount
    FROM
        datalake_retsuko.entry e
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
        contract_type ctt
            ON ctt.id_entry = e.id_external
    WHERE
        description != 'Crédito - Parcelamento corretagem - QuintoAndar'
    AND (
            (
                (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                  'adm-fee',
                  'lockin',
                  'adjustment-agreement-adm-fee',
                  'igpm-adm-fee',
                  'ipca-adm-fee',
                  'service-fee'
                  )
                )
            )
        )
    AND ct.country_code = 'BR'
    AND DATE(e.ts_created) >= '2024-01-01'
    AND NOT(ctt.contract_type = 'PJ' AND e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin'))
    AND af.type IN ('contract', 'tenant','landlord')
    AND at.type IN ('contract', 'tenant','landlord')
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8
    HAVING
        SUM(amount) != 0
),

retsuko AS (
    SELECT
        *
    FROM
        retsuko_pre

    UNION ALL

    SELECT
        *
    FROM
        retsuko_pos
),

retsuko_sum AS (
    SELECT DISTINCT
        i.id_external AS id_finance_entity,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') THEN 'adm fee'
            WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee', 'entry.bill-item/brokerage-quinto-andar') THEN 'brokerage quinto andar'
            WHEN e.bill_item = 'entry.bill-item/service-fee' THEN 'service fee'
        END AS revenue_name,
        i.accrual_year_month,
        CAST(SUM(e.amount) AS DECIMAL(12,2)) AS source_amount
    FROM
        treated_entry e
    INNER JOIN
        datalake_retsuko.invoice i
            ON e.id_invoice = i.id
    WHERE
        e.description != 'Crédito - Parcelamento corretagem - QuintoAndar'
    AND (
            (
                (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                  'adm-fee',
                  'brokerage-installment-fee',
                  'brokerage-quinto-andar',
                  'lockin',
                  'adjustment-agreement-adm-fee',
                  'igpm-adm-fee',
                  'ipca-adm-fee',
                  'service-fee'
                  )
                )
            )
        )
    AND i.status != 'canceled'
    AND DATE(i.ts_created) >= '2024-01-01'
    GROUP BY
        1, 2, 3, 4
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
        AND event IN ('tenant-invoices-paid', 'nota-fiscal-items', 'new-accounting-entries')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_finance_entity, event ORDER BY ts_updated DESC) = 1
),

sap_gateway AS (
    SELECT DISTINCT
        f.id_finance_entity,
        f.id_feature,
        f.sync_sap_status,
        MIN(IF(s.status IN ('done', 'waiting-unified-invoice'), 'success', 'failed')) as sync_sap_job_status
    FROM
        datalake_sap_gateway.feature f
    LEFT JOIN
        datalake_sap_gateway.sync_sap_job s
            ON f.id_feature = s.id_feature
    WHERE
        erp_solution = 'B1'
        AND type = 'NF'
    GROUP BY
        1, 2, 3
),

sap AS (
    SELECT
        id_finance_entity,
        CASE
            WHEN account_number = '31101.05.01' THEN 'service fee'
            WHEN account_number = '31101.02.01' THEN 'adm fee'
            WHEN account_number = '31101.01.01' THEN 'brokerage quinto andar'
        END AS revenue_account,
        account_number,
        MAX(DATE(dt_created)) AS dt_sap_created,
        MAX(DATE(dt_reference)) AS dt_sap_reference,
        CAST(SUM(debit_credit) AS DECIMAL(12,2)) AS sap_amount
    FROM
        datalake_accounting_funnel.ledger
    WHERE
        account_number LIKE '31101%'
        AND document_number LIKE 'IN %'
        AND dt_reference >= '2024-01-01'
    GROUP BY
        1, 2, 3
),
pre_df AS (
    SELECT
        'IN'||'-'||COALESCE(r.id_finance_entity, r.id_finance_entity_entry)||'-'||'1'||'-'||'1'||'-'||
        CASE
            WHEN r.revenue_name = 'adm fee' THEN '1'
            WHEN r.revenue_name = 'brokerage quinto andar' THEN '2'
            WHEN r.revenue_name = 'service fee' THEN '3' END AS id_retsuko_invoice_issuance,
        r.id_business_entity,
        contract_type,
        r.id_finance_entity,
        r.id_finance_entity_entry,
        se.version,
        s.account_number,
        source_name,
        r.revenue_name,
        accrual_year_month,
        CASE
            WHEN s.id_finance_entity IS NOT NULL THEN 'SUCCESS'
            WHEN s.id_finance_entity IS NULL AND sg.id_feature IS NOT NULL THEN 'SG FAILURE'
            WHEN s.id_finance_entity IS NULL AND sg.id_feature IS NULL THEN 'SB FAILURE'
        END AS status,
        source_amount,
        sap_amount,
        IF(s.id_finance_entity IS NULL OR sg.id_feature IS NULL, FALSE, TRUE) AS is_completeness_compliance,
        dt_source_trigger,
        dt_sap_created,
        dt_sap_reference
    FROM
        retsuko r
    LEFT JOIN
        sap_entity se
            ON r.id_entity = se.id_finance_entity
    LEFT JOIN
        sap_gateway sg
            ON se.id_sap_gateway_feature = sg.id_feature AND sg.sync_sap_job_status = 'success'
    LEFT JOIN
        sap s
            ON r.id_finance_entity = s.id_finance_entity
            AND r.revenue_name = s.revenue_account
),
df AS (
    SELECT
        id_retsuko_invoice_issuance,
        id_business_entity,
        id_finance_entity,
        id_finance_entity_entry,
        source_name,
        revenue_name,
        accrual_year_month,
        MIN(status) AS status,
        source_amount,
        SUM(sap_amount) AS sap_amount,
        MIN(is_completeness_compliance) AS is_completeness_compliance,
        dt_source_trigger,
        MAX(dt_sap_created) AS dt_sap_created,
        MAX(dt_sap_reference) AS dt_sap_reference,
        account_number,
        version,
        contract_type
    FROM
        pre_df
    GROUP BY
        1, 2, 3, 4, 5, 6, 7, 9, 12, 15, 16, 17
),
df_final AS (
    SELECT
        df.id_retsuko_invoice_issuance,
        df.id_business_entity,
        df.id_finance_entity,
        df.id_finance_entity_entry,
        df.version,
        df.contract_type,
        df.source_name,
        df.revenue_name,
        df.accrual_year_month,
        df.status,
        rs.source_amount,
        df.sap_amount,
        df.account_number,
        df.is_completeness_compliance,
        IF((ABS(rs.source_amount) - ABS(df.sap_amount)) >= 0.05 OR (ABS(rs.source_amount) - ABS(df.sap_amount)) <= -0.05 OR sap_amount IS NULL, FALSE, TRUE) AS is_correctness_compliance,
        IF(df.dt_sap_reference BETWEEN df.dt_source_trigger AND DATE_ADD(df.dt_source_trigger, 30), TRUE, FALSE) AS is_temporality_compliance,
        df.dt_source_trigger,
        df.dt_sap_created,
        df.dt_sap_reference
    FROM
        df
    LEFT JOIN
        retsuko_sum AS rs
            ON rs.id_finance_entity = df.id_finance_entity
            AND rs.revenue_name = df.revenue_name
)

SELECT
    id_retsuko_invoice_issuance,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    contract_type,
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
