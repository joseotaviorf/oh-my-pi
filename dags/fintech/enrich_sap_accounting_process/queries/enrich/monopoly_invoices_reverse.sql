WITH 
monopoly AS (
    SELECT
        st.id AS id_finance_entity,
        ae.id,
        ae.id_sale_transaction,
        CASE
            WHEN sr.id_state_external = '11' THEN '420008'
            ELSE '420007'
        END AS account_number,
        CASE
            WHEN sr.id_state_external = '11' THEN 'Casa Mineira'
            ELSE 'Plataforma QuintoAndar'
        END AS source_name,
        s.id_external_offer,
        st.id_external_sync AS id_feature,
        ne.error_type,
        SUM(ae.credit) AS source_amount,
        MIN(sr.dt_notary_start) AS dt_source_trigger,
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
    LEFT JOIN datalake_monopoly_clean.nota_fiscal_emission_error ne
        ON s.id = ne.id_sale
    WHERE
      sr.dt_notary_start >= '2025-01-01'
      AND st.id_external_sync IS NOT NULL
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),
sap_gateway AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
    s.type,
    s.status as sync_sap_job_status,
    w.status as sap_send_status,
    w.webhook_status as sap_processed_status,
    w.errors AS webhook_error
  FROM
    datalake_sap_gateway_clean.feature f
  LEFT JOIN
    datalake_sap_gateway_clean.sync_sap_job s
      ON f.id_feature = s.id_feature
  LEFT JOIN
    datalake_sap_gateway_clean.webhook_log w
      ON s.idoc = w.idoc
  WHERE 1=1
    AND s.erp_solution IN ('S4')
    AND s.type IN ('NF')
    AND s.status NOT IN ('ignore', 'ignored')
    AND DATE(f.ts_created) >= DATE('2025-01-01')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature ORDER BY s.ts_updated) = 1  
),
sap_gateway_base AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
    s.type,
    s.status AS sync_sap_job_status,
    w.status AS sap_send_status,
    w.webhook_status AS sap_processed_status,
    w.errors AS webhook_error
  FROM
    datalake_sap_gateway_clean.feature f
  LEFT JOIN
    datalake_sap_gateway_clean.sync_sap_job s
      ON f.id_feature = s.id_feature
  LEFT JOIN
    datalake_sap_gateway_clean.webhook_log w
      ON s.idoc = w.idoc
  WHERE 1=1
    AND s.erp_solution IN ('S4')
    AND s.type IN ('NF')
    AND s.status NOT IN ('ignore', 'ignored')
    AND DATE(f.ts_created) >= DATE('2025-01-01')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature, s.hash ORDER BY s.ts_updated) = 1  
),
sap_ledger AS (
SELECT
    l.id_finance_entity,
    l.id_finance_entity_entry,
    l.account_number,
    l.accrual_year_month,
    sg.id_feature,
    SUM(l.debit_credit) AS debit_credit,
    MAX(DATE(l.dt_created)) AS dt_sap_created,
    MAX(DATE(l.dt_reference)) AS dt_sap_reference
  FROM
    datalake_pas.ledger l
  INNER JOIN 
    sap_gateway_base sg ON l.hash = sg.hash
  WHERE 1=1
    AND dt_reference >= DATE('2025-01-01')
    AND account_number IN ('420007','420008')
  GROUP BY 1, 2, 3, 4, 5
)
  SELECT
    ('RE-MNPL-I-' || sl.id_finance_entity || '-' || COALESCE(sl.account_number, '')) id_accounting_process, 
    sl.id_feature AS id_business_entity,
    sl.id_finance_entity AS id_finance_entity,
    sl.id_finance_entity_entry,
    CAST(NULL AS STRING) AS version,
    'for sale' AS business_unit,
    'S4' AS source_name,
    'invoice' AS accounting_type,
    sl.account_number,
    CASE
      WHEN sl.account_number = '420008' THEN 'Brokerage (Casa Mineira)'
      WHEN sl.account_number = '420007' THEN 'Brokerage (Platform)'
      WHEN sl.account_number = '420032' THEN 'Provision - Brokerage (Platform)'
      ELSE CAST(NULL AS STRING)
    END AS accounting_name,
    sl.accrual_year_month,
    'reverse straw failure' AS accounting_process_status,
    MIN(CASE
      WHEN m.id_feature IS NULL AND sg.id_feature IS NULL THEN 'manual transaction'
      WHEN m.id_feature IS NULL AND sg.id_feature IS NOT NULL THEN 'wrong account number or postponed entry'
      ELSE NULL
    END) AS error_description,
    FALSE AS is_completeness,
    FALSE AS is_correctness,
    FALSE AS is_temporality,
    FALSE AS is_compliance,
    CAST(SUM(m.source_amount) AS DECIMAL(12,2)) AS source_amount,
    CAST(SUM(sl.debit_credit) AS DECIMAL(12,2)) AS sap_amount,
    MAX(m.dt_source_trigger) AS dt_source_trigger,
    MAX(sl.dt_sap_created) AS dt_sap_created,
    MAX(sl.dt_sap_reference) AS dt_sap_reference
  FROM
    sap_ledger sl
  LEFT JOIN
    sap_gateway sg
      ON sl.id_feature = sg.id_feature
  LEFT JOIN
    monopoly m
      ON sl.id_feature = m.id_feature
  WHERE m.id_feature IS NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15, 16, 17