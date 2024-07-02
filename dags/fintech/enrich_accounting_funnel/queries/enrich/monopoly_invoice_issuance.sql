WITH monopoly AS (
    SELECT
        ae.id,
        ae.id_sale_transaction,
        CASE
            WHEN sr.id_state_external = '11' THEN 'Casa Mineira'
            ELSE 'Plataforma QuintoAndar'
        END AS sale_source,
        SUM(ae.credit) AS source_amount,
        s.id_external_offer,
        st.id_external_sync,
        MIN(sr.dt_notary_start) AS dt_trigger,
        SUM(sr.total_payment_amount * sr.brokerage_fee * sr.brokerage_quintoandar_fee) AS credit
    FROM
        datalake_monopoly_clean.sale s
    LEFT JOIN datalake_monopoly_clean.sale_revision sr
        ON s.id = sr.id
        AND s.current_revision = sr.revision
    LEFT JOIN datalake_monopoly_clean.sale_transaction st
        ON st.id_sale = s.id AND st.event = 'nf-issued'
    LEFT JOIN datalake_monopoly_clean.accounting_entry ae
        ON ae.id_sale_transaction = st.id AND ae.person_type = 'income'
    GROUP BY 1,2,3,5,6
),

sap_gateway AS (
    SELECT DISTINCT
        f.id_finance_entity,
        f.id_feature,
        s.hash,
        f.sync_sap_status, 
        MIN(IF(s.status = 'done', 'success', 'failed')) AS sync_sap_job_status
    FROM
        datalake_sap_gateway.feature f
    LEFT JOIN
        datalake_sap_gateway.sync_sap_job s
            ON f.id_feature = s.id_feature 
    WHERE 
        erp_solution = 'B1'
        AND type = 'NF'
    GROUP BY 
        1, 2, 3, 4
),

sap AS (
    SELECT 
        id_business_entity,
        id_finance_entity,
        hash,
        account_number,
        MAX(DATE(dt_created)) AS dt_sap_created,
        MAX(DATE(dt_reference)) AS dt_sap_reference,
        CAST(SUM(debit_credit) AS DECIMAL(12,2)) AS sap_amount
    FROM 
        datalake_accounting_funnel.ledger
    WHERE 
        account_number IN ('31101.04.01', '31101.04.09')
        AND document_number LIKE 'IN %'
        AND dt_reference >= DATE('2024-01-01')
    GROUP BY 
        1, 2, 3, 4
),

df AS (
SELECT
    m.id_external_offer,
    s.id_business_entity,
    s.id_finance_entity,
    m.sale_source,
    s.account_number,
    m.source_amount,
    m.credit,
    SUM(s.sap_amount) AS sap_amount,
    m.dt_trigger,
    s.dt_sap_created,
    s.dt_sap_reference
FROM 
    monopoly m 
LEFT JOIN 
    sap_gateway sg 
        ON sg.id_feature = m.id_external_sync
LEFT JOIN 
    sap s 
        ON s.hash = sg.hash
WHERE 
    dt_trigger >= DATE('2023-01-01')
GROUP BY 1,2,3,4,5,6,7,9,10,11
)

SELECT
    id_external_offer AS id_business_entity,
    sale_source,
    ROUND(COALESCE(source_amount, credit),2) AS source_amount,
    sap_amount,
    account_number,
    IF((ABS(source_amount) - ABS(sap_amount)) >= 0.05 OR (ABS(source_amount) - ABS(sap_amount)) <= -0.05 OR sap_amount IS NULL, FALSE, TRUE) AS is_compliance,
    dt_trigger AS dt_source_trigger,
    dt_sap_created,
    dt_sap_reference
FROM 
    df 
