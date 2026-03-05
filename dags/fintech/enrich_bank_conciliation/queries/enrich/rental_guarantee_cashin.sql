WITH rental_guarantee_and_bank AS (
  SELECT 
    s.id,
    s.id_business_entity,
    s.id_finance_entity,
    s.id_feature,
    p.id_transaction,
    s.id_external_payment,
    s.transaction_name,
    s.sap_status,
    s.trigger,
    s.ts_created,
    s.description,
    s.request,
    itau.origin_identifier,
    itau.literal_complete,
    s.amount AS rental_guarantee_amount,
    itau.amount_value AS bank_amount,
    checkout_charge.due_amount AS checkout_amount
  FROM 
    datalake_rental_guarantee_clean.sap s
  LEFT JOIN
    datalake_rental_guarantee_clean.charge AS c
        ON c.id = s.id_finance_entity
        AND c.id_guarantee = s.id_business_entity
  LEFT JOIN
    datalake_checkout_clean.pix AS p
        ON p.id_transaction = c.id_external
  LEFT JOIN
    datalake_checkout_clean.charge AS checkout_charge
        ON checkout_charge.id = p.id_charge
  LEFT JOIN 
    datalake_itau_statements_clean.statement_879200429691 AS itau
      ON itau.origin_identifier = p.id_bank_payment
  WHERE 1=1 
  AND s.sap_status = 'SUCCESS'
  AND s.trigger = 'PIX_PAYMENT_CONFIRMATION'
  AND s.ts_created >= '2025-08-01'
),
sap_gateway AS (
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
    AND s.status NOT IN ('ignore', 'ignored')
    AND DATE(f.ts_created) >= DATE('2024-01-01')
    AND hash is not null
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.id_finance_entity, s.id_feature, s.hash ORDER BY s.ts_updated) = 1 
),
sap_ledger AS (
  SELECT
    l.id_finance_entity,
    l.id_finance_entity_entry,
    l.account_number,
    l.hash,
    l.debit_credit AS sap_amount,
    l.dt_created,
    l.dt_reference
  FROM
    datalake_pas.ledger l
  WHERE 1=1
    AND dt_reference >= DATE('2024-01-01')
    AND account_number IN ('113002', '110160X')
    ORDER BY account_number
)
SELECT 
  rg.id,
  rg.id_business_entity,
  rg.id_finance_entity,
  rg.id_feature,
  rg.id_transaction,
  rg.id_external_payment,
  rg.transaction_name,
  rg.sap_status,
  rg.trigger,
  rg.ts_created,
  rg.description,
  rg.request,
  rg.origin_identifier,
  rg.literal_complete,
  sg.hash,
  rg.rental_guarantee_amount,
  rg.bank_amount,
  rg.checkout_amount,
  sl.sap_amount
FROM 
  rental_guarantee_and_bank AS rg 
LEFT JOIN 
  sap_gateway AS sg 
    ON rg.id_feature = sg.id_feature
LEFT JOIN 
  sap_ledger AS sl 
    ON sg.hash = sl.hash
    AND rg.id_finance_entity = sl.id_finance_entity
WHERE 1 = 1 
