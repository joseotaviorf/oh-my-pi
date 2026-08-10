WITH 
sap_gateway_ranked AS (
    SELECT
        f.id_source AS id_finance_entity,
        f.sync_sap_status,
        s.status,
        s.hash,
        RANK() OVER (PARTITION BY f.id_source ORDER BY s.ts_updated DESC) AS rn
    FROM
        datalake_sap_gateway_clean.feature f
    LEFT JOIN
        datalake_sap_gateway_clean.sync_sap_job s
            ON f.id_feature = s.id_feature
    WHERE
        f.source = 'kill-queue/reservation'
        AND s.type = 'NF'
),
sap_gateway AS (
    SELECT
        id_finance_entity,
        sync_sap_status,
        status,
        hash
    FROM
        sap_gateway_ranked
    WHERE
        rn = 1
)

, sap_ledger AS (
    SELECT
      id_business_entity,
      id_finance_entity,
      id_finance_entity_entry,
      id_transaction,
      CAST(id_external_payment AS INT) AS id_external_payment,
      account_number,
      accrual_year_month,
      SUM(debit_credit) AS debit_credit,
      MAX(DATE(dt_created)) AS dt_sap_created,
      MAX(DATE(dt_reference)) AS dt_sap_reference
    FROM
      datalake_accounting_funnel.ledger
    WHERE
      dt_reference >= DATE('2025-01-01')
      AND account_number IN ('420006')
    GROUP BY 1, 2, 3, 4, 5, 6, 7
)

, kill_queue_ranked AS (
    SELECT
        r.id_tenant AS id_business_entity,
        r.id AS id_finance_entity,
        'reservation fee' AS accounting_name,
        'for rent' AS business_unit,
        'kill queue' AS source_name,
        'invoice' AS accounting_type,
        r.value AS source_amount,
        r.status,
        r.last_charge_status,
        DATE(r.ts_created) AS dt_source_trigger,
        r.ts_updated,
        RANK() OVER (PARTITION BY r.id ORDER BY r.ts_updated DESC) AS rn
    FROM
        datalake_kill_queue_clean.reservation r
    WHERE
        r.status IN ('FINISHED', 'CANCELED')
        AND r.ts_created >='2024-01-01'
),
kill_queue AS (
    SELECT
        id_business_entity,
        id_finance_entity,
        accounting_name,
        business_unit,
        source_name,
        accounting_type,
        source_amount,
        status,
        last_charge_status,
        dt_source_trigger,
        ts_updated
    FROM
        kill_queue_ranked
    WHERE
        rn = 1
)

SELECT
    ('KK-I-' || sl.id_transaction || '-' || COALESCE(sl.account_number, '')) AS id_accounting_process,
    sl.id_business_entity,
    sl.id_finance_entity,
    sl.id_finance_entity_entry,
    CAST(NULL AS STRING) AS version,
    'for rent' AS business_unit,
    'S4' AS source_name,
    'invoice' AS accounting_type,
    sl.account_number,
    r.accounting_name,
    sl.accrual_year_month,
    'reverse straw failure' AS accounting_process_status,
    CASE
        WHEN r.id_finance_entity IS NULL AND sg.id_finance_entity IS NULL THEN 'manual transaction'
        WHEN r.id_finance_entity IS NULL AND sg.id_finance_entity IS NOT NULL THEN 'transaction missing in sap entity'
        WHEN r.id_finance_entity IS NULL AND sg.id_finance_entity IS NOT NULL THEN 'wrong account number or postponed entry'
        ELSE NULL
    END AS error_description,
    FALSE AS is_completeness,
    FALSE AS is_correctness,
    FALSE AS is_temporality,
    FALSE AS is_compliance,
    CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
    CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
    r.dt_source_trigger AS dt_source_trigger,
    sl.dt_sap_created AS dt_sap_created,
    sl.dt_sap_reference AS dt_sap_reference
    FROM
        sap_ledger sl 
    LEFT JOIN
        sap_gateway sg
            ON sg.id_finance_entity = sl.id_finance_entity 
    LEFT JOIN
        kill_queue r
        ON COALESCE(sl.id_finance_entity, sg.id_finance_entity) = r.id_finance_entity
 WHERE 1=1
 AND r.id_finance_entity IS NULL
