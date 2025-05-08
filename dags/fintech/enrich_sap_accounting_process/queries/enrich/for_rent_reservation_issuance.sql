WITH sap_gateway AS (
    SELECT
        f.id_source,
        f.sync_sap_status,
        s.status,
        s.hash
    FROM
        datalake_sap_gateway_clean.feature f
    LEFT JOIN
        datalake_sap_gateway_clean.sync_sap_job s
            ON f.id_feature = s.id_feature
    WHERE
        f.source = 'kill-queue/reservation'
        AND s.type = 'NF'
    QUALIFY RANK() OVER (PARTITION BY f.id_source ORDER BY s.ts_updated DESC) = 1
)

, sap AS (
  SELECT
        id_finance_entity,
        accrual_year_month,
        CASE
            WHEN account_number = '420006' THEN 'reservation fee'
        END AS revenue_account,
        account_number,
        MAX(DATE(dt_created)) AS dt_sap_created,
        MAX(DATE(dt_reference)) AS dt_sap_reference,
        CAST(SUM(debit_credit) AS DECIMAL(12,2)) AS sap_amount
    FROM
        datalake_accounting_funnel.ledger
    WHERE
        account_number = '420006'
        AND dt_reference >= '2024-01-01'
    GROUP BY
        1, 2, 3, 4
)

, kill_queue AS (
    SELECT
        r.id_tenant AS id_business_entity,
        r.id AS id_finance_entity,
        'kill_queue' AS source_name,
        '420006' AS account_number,
        'reservation_fee' AS revenue_name,
        r.value AS source_amount,
        r.status,
        r.last_charge_status,
        DATE(r.ts_created) AS dt_source_trigger,
        r.ts_updated
    FROM
        datalake_kill_queue_clean.reservation r
    WHERE
        r.status IN ('FINISHED', 'CANCELED')
        AND r.ts_created >='2024-01-01'
    QUALIFY RANK() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
)

, df AS (
    SELECT
      k.id_business_entity,
      k.id_finance_entity,
      CAST(NULL AS INT) AS id_finance_entity_entry,
      k.source_name,
      k.revenue_name,
      k.account_number,
      s.accrual_year_month,
      CASE
          WHEN s.id_finance_entity IS NOT NULL THEN 'SUCCESS'
          WHEN s.id_finance_entity IS NULL AND sg.id_source IS NOT NULL THEN 'SG FAILURE'
          WHEN s.id_finance_entity IS NULL AND sg.id_source IS NULL THEN 'SOURCE FAILURE'
      END AS status,
      MIN(IF(s.id_finance_entity IS NULL, FALSE, TRUE)) AS is_completeness_compliance,
      CAST(k.source_amount AS DECIMAL(12,2)) AS source_amount,
      CAST(s.sap_amount AS DECIMAL(12,2)) AS sap_amount,
      MAX(dt_source_trigger) AS dt_source_trigger,
      MAX(dt_sap_created) AS dt_sap_created,
      MAX(dt_sap_reference) AS dt_sap_reference
    FROM
        kill_queue k
    LEFT JOIN
        sap s
            ON k.id_finance_entity = s.id_finance_entity
    LEFT JOIN
        sap_gateway sg
            ON k.id_finance_entity = sg.id_source
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 10, 11
)

, df_final AS (
    SELECT
        'IN'||'-'||COALESCE(df.id_finance_entity, df.id_business_entity||df.accrual_year_month)||'-'||'1'||'-'||'2'||'-'|| '1' AS id_kill_queue_invoice_issuance,
        df.id_business_entity,
        df.id_finance_entity,
        df.id_finance_entity_entry,
        --df.version,
        --df.contract_type,
        df.source_name,
        df.revenue_name,
        df.accrual_year_month,
        df.status,
        df.source_amount,
        df.sap_amount,
        df.account_number,
        df.is_completeness_compliance,
        IF((ABS(df.source_amount) - ABS(df.sap_amount)) >= 0.05 OR (ABS(df.source_amount) - ABS(df.sap_amount)) <= -0.05 OR sap_amount IS NULL, FALSE, TRUE) AS is_correctness_compliance,
        IF(df.dt_sap_reference BETWEEN df.dt_source_trigger AND DATE_ADD(df.dt_source_trigger, 30), TRUE, FALSE) AS is_temporality_compliance,
        df.dt_source_trigger,
        df.dt_sap_created,
        df.dt_sap_reference
    FROM
        df
)

SELECT DISTINCT
    id_kill_queue_invoice_issuance,
    id_business_entity,
    id_finance_entity,
    id_finance_entity_entry,
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
