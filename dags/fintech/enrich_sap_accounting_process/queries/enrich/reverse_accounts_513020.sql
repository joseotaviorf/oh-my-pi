WITH sap AS (
    SELECT
        l.id_business_entity,
        regexp_replace(l.id_finance_entity, '[^0-9]', '') AS id_finance_entity,
        l.id_finance_entity_entry,
        l.hash,
        l.account_number,
        l.account_name,
        SUM(l.debit_credit) OVER (PARTITION BY regexp_replace(l.id_finance_entity, '[^0-9]', '')) AS sap_amount,
        l.dt_reference AS dt_sap_reference,
        l.dt_created AS dt_sap_created
    FROM 
        datalake_accounting_funnel.ledger AS l
    WHERE 
        account_number = '513020'
        AND dt_reference >= DATE('2025-01-01')
        AND source_client NOT IN ('rental-guarantee-pla')
),

sap_gateway AS (
  SELECT
    f.id_finance_entity,
    s.id_feature,
    s.hash,
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
  WHERE
    s.erp_solution IN ('S4')
    AND s.type = 'LCM'
    AND s.status NOT IN ('ignore', 'ignored')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature ORDER BY s.ts_updated) = 1
),

retsuko AS (
    SELECT DISTINCT
        ct.id_external AS id_business_entity,
        i.id_external AS id_finance_entity,
        se.id_sap_gateway_feature,
        se.version,
        se.event,
        se.status,
        se.failed_status,
        se.failed_reason,
        i.accrual_year_month,
        CAST(i.due_amount AS DECIMAL(12,2)) AS retsuko_amount,
        DATE(i.ts_write_off) AS dt_source_trigger
    FROM
        datalake_retsuko.entry  e
    INNER JOIN
        datalake_retsuko_clean.account AS af
            ON e.id_from_account = af.id
    INNER JOIN
        datalake_retsuko_clean.account AS at
            ON e.id_to_account = at.id
    LEFT JOIN
        datalake_retsuko.invoice AS i
            ON e.id_invoice = i.id
    LEFT JOIN
        datalake_retsuko_clean.contract AS ct
            ON ct.id = e.id_contract
    LEFT JOIN 
        datalake_retsuko_clean.sap_entity AS se
            ON se.id_finance_entity = i.id_external
    WHERE
        TRUE
        AND i.is_write_off = True
        AND ct.country_code = 'BR'
        AND af.type IN ('contract', 'tenant','landlord')
        AND at.type IN ('contract', 'tenant','landlord')
        AND i.reason NOT IN ('write-off-negotiation-cyber', 'write-off-negotiation-5A')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY se.id_finance_entity, se.event ORDER BY se.ts_updated DESC) = 1
),

df AS (
    SELECT 
        'RE-RTSK-WO'||'-'||s.id_finance_entity||'-'||COALESCE(s.account_number, '') AS id_accounting_process,
        s.id_business_entity,
        s.id_finance_entity,
        CAST(NULL AS STRING) AS id_finance_entity_entry,
        r.version,
        s.account_number,
        r.retsuko_amount,
        CAST(s.sap_amount AS DECIMAL(12,2)) AS sap_amount,
        r.accrual_year_month,
        'reverse straw failure' AS accounting_process_status,
        MIN(CASE
          WHEN r.id_finance_entity IS NULL AND r.id_sap_gateway_feature IS NULL AND sg.id_finance_entity IS NULL THEN 'manual transaction'
          WHEN r.id_finance_entity IS NULL AND r.id_sap_gateway_feature IS NULL AND sg.id_finance_entity IS NOT NULL THEN 'transaction missing in sap entity'
          WHEN r.id_finance_entity IS NULL AND r.id_sap_gateway_feature IS NOT NULL AND sg.id_finance_entity IS NOT NULL THEN 'wrong account number'
          ELSE NULL
        END) AS error_description,
        FALSE AS is_completeness,
        FALSE AS is_correctness,
        FALSE AS is_temporality,
        FALSE AS is_compliance,
        r.dt_source_trigger,
        MAX(s.dt_sap_reference) AS dt_sap_reference,
        MAX(s.dt_sap_created) AS dt_sap_created
    FROM 
        sap AS s
    LEFT JOIN
        sap_gateway AS sg 
            ON s.hash = sg.hash
    LEFT JOIN 
        retsuko AS r
            ON sg.id_feature = r.id_sap_gateway_feature
            OR s.id_finance_entity = CAST(r.id_finance_entity AS STRING)
    WHERE 
        r.id_finance_entity IS NULL
    GROUP BY 
        ALL
)

SELECT 
    id_accounting_process||'-'||ROW_NUMBER() OVER (PARTITION BY id_accounting_process ORDER BY dt_sap_created) AS id_accounting_process,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
    version,
    'for rent' AS business_unit,
    's4' AS source_name,
    'write-off' AS accounting_type,
    account_number,
    'write-off' AS accounting_name,
    retsuko_amount AS source_amount,
    sap_amount,
    is_completeness,
    is_correctness,
    is_temporality,
    is_compliance,
    accounting_process_status,
    error_description,
    accrual_year_month,
    dt_source_trigger,
    dt_sap_reference,
    dt_sap_created
FROM 
    df 
