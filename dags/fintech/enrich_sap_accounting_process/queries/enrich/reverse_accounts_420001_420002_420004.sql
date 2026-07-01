WITH original_invoice AS (
    SELECT
        id_original_invoice_external,
        MAX(ts_due) AS ts_due_original,
        MIN (id_external) id_invoice
    FROM
        datalake_retsuko.invoice
    WHERE
        ts_nf_requested IS NOT NULL
    GROUP BY 
        1
),

retsuko_brokerage AS (
  SELECT DISTINCT
        ct.id_external AS id_business_entity,
        ct.landlord_legal_person AS contract_type,
        i.id_external AS id_finance_entity,
        CAST(NULL AS INT) AS id_finance_entity_entry,
        COALESCE(o.id_invoice, i.id_external) AS id_entity,
        o.id_invoice AS id_original_invoice,
        'seu barriga' AS source_name,
        CASE
            WHEN e.bill_item = 'entry.bill-item/brokerage-quinto-andar' THEN '420001'
            WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'juridical' THEN '420002'
            WHEN e.bill_item = 'entry.bill-item/brokerage-installment-fee' THEN '420004'
        END AS account_number,
        CASE
            WHEN e.bill_item = 'entry.bill-item/brokerage-quinto-andar' THEN 'brokerage quinto andar'
            WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'juridical' THEN 'adm fee PJ'
            WHEN e.bill_item = 'entry.bill-item/brokerage-installment-fee' THEN 'brokerage installment fee'
        END AS accounting_name,
        i.accrual_year_month,
        MAX(CASE
            WHEN e.bill_item = 'entry.bill-item/pro-guarantor-5A-installment' THEN last_day(e.ts_created)
            WHEN o.id_invoice IS NOT NULL THEN DATE(o.ts_due_original)
            ELSE DATE(i.ts_due)
        END) AS dt_source_trigger,
        CAST(SUM(amount) AS DECIMAL(12,2)) AS source_amount,
        MAX(e.accounting_version) AS accounting_version
    FROM
        datalake_retsuko.entry e
    INNER JOIN
        datalake_retsuko.invoice i
            ON e.id_invoice = i.id
    LEFT JOIN
        original_invoice o
            ON i.id_original_invoice_external = o.id_original_invoice_external
    INNER JOIN
        datalake_retsuko.invoice_info ii
            ON ii.id_invoice = i.id_external
    INNER JOIN
        datalake_retsuko_clean.contract ct
            ON ct.id = i.id_contract
    WHERE
        description != 'Crédito - Parcelamento corretagem - QuintoAndar'
        AND (e.bill_item IN ('entry.bill-item/pro-guarantor-5A-installment') OR 
        (
            (ii.invoice_user = 'landlord')
            AND (NOT(i.ts_due > current_date AND i.accrual_year_month < 202405))
            AND e.bill_item IN ('entry.bill-item/brokerage-quinto-andar', 'entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin', 'entry.bill-item/brokerage-installment-fee')
        )
      )
    GROUP BY 
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10
      HAVING
          SUM(amount) != 0
),
retsuko_adm_service_fee AS (
  SELECT 
      ct.id_external AS id_business_entity,
      ct.landlord_legal_person AS contract_type,
      i.id_external AS id_finance_entity,
      CAST(NULL AS INT) AS id_finance_entity_entry,
      COALESCE(o.id_invoice, i.id_external) AS id_entity,
      o.id_invoice AS id_original_invoice,
      'seu barriga' AS source_name,
      CASE
        WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'physical' THEN '420002'
        WHEN e.bill_item = 'entry.bill-item/service-fee' THEN '420005'
      END AS account_number,
      CASE
        WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') AND ct.landlord_legal_person = 'physical' THEN 'adm fee PF'
        WHEN e.bill_item = 'entry.bill-item/service-fee' THEN 'service fee'
      END AS accounting_name,
      i.accrual_year_month,
      MAX(CASE
        WHEN o.id_invoice IS NOT NULL THEN DATE(o.ts_due_original)
        ELSE DATE(i.ts_due)
      END) AS dt_source_trigger,
      CAST(SUM(amount) AS DECIMAL(12,2)) AS source_amount,
      MAX(e.accounting_version) AS accounting_version
  FROM
    datalake_retsuko.entry e
  INNER JOIN
    datalake_retsuko_clean.account AS af
      ON e.id_from_account = af.id
  INNER JOIN
    datalake_retsuko_clean.account AS at
      ON e.id_to_account = at.id
  INNER JOIN
    datalake_retsuko.invoice i
      ON e.id_invoice = i.id
  LEFT JOIN
    original_invoice o
      ON i.id_original_invoice_external = o.id_original_invoice_external
  INNER JOIN
    datalake_retsuko.invoice_info ii
      ON ii.id_invoice = i.id_external
  INNER JOIN
    datalake_retsuko_clean.contract ct
      ON ct.id = i.id_contract
  WHERE 1=1
    AND ct.country_code = 'BR'
    AND af.type IN ('contract', 'tenant', 'landlord')
    AND at.type IN ('contract', 'tenant','landlord')
    AND i.status != 'canceled'
    AND description != 'Crédito - Parcelamento corretagem - QuintoAndar'
    AND  e.bill_item IN ('entry.bill-item/service-fee')
         OR (ct.landlord_legal_person = 'physical' 
            AND e.bill_item IN (
              'entry.bill-item/adm-fee', 
              'entry.bill-item/igpm-adm-fee', 
              'entry.bill-item/ipca-adm-fee', 
              'entry.bill-item/adjustment-agreement-adm-fee', 
              'entry.bill-item/lockin')
            )
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
  HAVING
      SUM(amount) != 0
),

retsuko AS (
  SELECT * FROM retsuko_brokerage
  UNION ALL
  SELECT * FROM retsuko_adm_service_fee
),

sap_entity AS (
    SELECT
        id_finance_entity,
        id_sap_gateway_feature,
        event,
        status,
        failed_status,
        failed_reason
    FROM
        datalake_retsuko_clean.sap_entity
    WHERE
        id_finance_entity IS NOT NULL
        AND event IN ('tenant-invoices-paid', 'nota-fiscal-items', 'new-accounting-entries')
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
    WHERE
        s.erp_solution IN ('S4')
        AND s.type IN ('NF', 'PN')
        AND s.status NOT IN ('ignore', 'ignored')
        AND DATE(f.ts_created) >= DATE('2024-01-01')
),

sap_ledger AS (
    SELECT
        id_business_entity,
        id_finance_entity,
        hash,
        id_transaction,
        account_number,
        created_by,
        SUM(debit_credit) AS debit_credit,
        MAX(DATE(dt_created)) AS dt_sap_created,
        MAX(DATE(dt_reference)) AS dt_sap_reference
    FROM
        datalake_pas.ledger
    WHERE
        dt_reference >= DATE('2025-01-01')
        AND (account_number IN ('420001', '420002', '420004') 
             OR (account_number IN ('420005') AND dt_reference >= DATE('2026-08-01'))
            )
        AND ((source_client NOT IN ('rental-guarantee-pla')) OR (source_client IS NULL))
    GROUP BY 
        1, 2, 3, 4, 5, 6
    HAVING 
        SUM(debit_credit) != 0
)

SELECT
    ('RE-RTSK-I-' || sl.id_transaction || '-' || COALESCE(sl.account_number, '')) AS id_accounting_process,
    sl.id_business_entity,
    sl.id_finance_entity,
    CAST(NULL AS INT) AS id_finance_entity_entry,
    MAX(r.accounting_version) AS version,
    'for rent' AS business_unit,
    's4' AS source_name,
    'revenue accounting' AS accounting_type,
    sl.account_number,
    r.accounting_name,
    CAST(r.source_amount AS DECIMAL(12,2)) AS source_amount,
    CAST(sl.debit_credit AS DECIMAL(12,2)) AS sap_amount,
    FALSE AS is_completeness,
    FALSE AS is_correctness,
    FALSE AS is_temporality,
    FALSE AS is_compliance,
    'reverse straw failure' AS accounting_process_status,
    MIN(CASE
      WHEN r.id_entity IS NULL AND se.id_finance_entity IS NULL AND sg.id_finance_entity IS NULL THEN 'manual transaction'
      WHEN r.id_entity IS NULL AND se.id_finance_entity IS NULL AND sg.id_finance_entity IS NOT NULL THEN 'transaction missing in sap entity'
      WHEN r.id_entity IS NULL AND se.id_finance_entity IS NOT NULL AND sg.id_finance_entity IS NOT NULL THEN 'wrong account number'
      ELSE NULL
    END) AS error_description,
    r.accrual_year_month,
    MAX(r.dt_source_trigger) AS dt_source_trigger,
    MAX(sl.dt_sap_created) AS dt_sap_created,
    MAX(sl.dt_sap_reference) AS dt_sap_reference
FROM
    sap_ledger sl
LEFT JOIN
    sap_gateway sg
        ON sl.hash = sg.hash
LEFT JOIN 
    sap_entity se
        ON sg.id_feature = se.id_sap_gateway_feature
LEFT JOIN
    retsuko r
        ON (r.id_entity = se.id_finance_entity) OR 
        (r.account_number = sl.account_number AND sl.id_finance_entity = r.id_finance_entity) OR 
        (r.account_number = sl.account_number AND sl.id_finance_entity = r.id_entity)
WHERE   
    r.id_finance_entity IS NULL
GROUP BY ALL