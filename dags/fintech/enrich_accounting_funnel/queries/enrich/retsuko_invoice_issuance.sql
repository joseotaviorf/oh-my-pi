WITH grouped_adm_fee AS (
SELECT *, 
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
SELECT *, 
    SUM(amount) OVER (partition by i.id_external, e.bill_item_grouped) as agg
FROM 
    grouped_adm_fee e 
INNER JOIN 
    datalake_retsuko.invoice i 
    ON e.id_invoice = i.id  
),

retsuko AS (
  SELECT DISTINCT
    ct.id_external AS id_contract,
    i.id_external AS id_invoice,
    'seu barriga' AS source_name,
    CASE
      WHEN e.bill_item = 'entry.bill-item/service-fee' THEN 'service fee'
      WHEN e.bill_item IN ('entry.bill-item/adm-fee', 'entry.bill-item/igpm-adm-fee', 'entry.bill-item/ipca-adm-fee', 'entry.bill-item/adjustment-agreement-adm-fee', 'entry.bill-item/lockin') THEN 'adm fee'
      WHEN e.bill_item IN ('entry.bill-item/brokerage-installment-fee', 'entry.bill-item/brokerage-quinto-andar') THEN 'brokerage'
    END AS revenue_name,
    i.accrual_year_month,
    DATE(i.ts_created) AS dt_source_created,
    DATE(i.ts_paid) AS dt_source_paid,
    CAST(SUM(amount) AS DECIMAL(12,2)) AS product_amount
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
  WHERE 
      description != 'Crédito - Parcelamento corretagem - QuintoAndar' 
  AND agg > 0
  AND (
          (
              (ii.invoice_user = 'landlord') AND 
              (i.ts_due < current_date) AND
              (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                'adm-fee',  
                'brokerage-installment-fee', 
                'brokerage-quinto-andar', 
                'lockin', 
                'pro-guarantor-5A-installment', 
                'adjustment-agreement-adm-fee', 
                'igpm-adm-fee', 
                'ipca-adm-fee'
                )
              ) 
          ) 
  OR 
          (
              (ii.invoice_user = 'tenant') AND 
              (i.status IN ('paid', 'written-down', 'not-payable')) AND
              (i.ts_due < current_date) AND
              (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                'service-fee'
                )            
              )
          )
      )
  AND ct.country_code = 'BR'
  AND ii.invoice_frequency != 'extra'
  AND DATE(i.ts_created) >= '2024-01-01'
  GROUP BY
      1, 2, 3, 4, 5, 6, 7
  HAVING 
    SUM(amount) != 0
),

sap AS (
  SELECT 
    id_finance_entity,
    CASE
      WHEN account_number = '31101.05.01' THEN 'service fee'
      WHEN account_number = '31101.02.01' THEN 'adm fee'
      WHEN account_number = '31101.01.01' THEN 'brokerage'
    END AS revenue_account,
    DATE(dt_created) AS dt_sap_created,
    DATE(dt_reference) AS dt_sap_reference,
    CAST(sum(debit_credit) AS DECIMAL(12,2)) AS sap_amount
  FROM 
    datalake_accounting_funnel.ledger
  WHERE 
    account_number LIKE '31101%'
  AND document_number LIKE 'IN %'
  AND dt_reference >= '2024-01-01'
  GROUP BY 
    1, 2, 3, 4
)

SELECT 
  'IN'||'-'||id_invoice||'-'||'1'||'-'|| 
    CASE
      WHEN revenue_name = 'adm fee' THEN '1'
      WHEN revenue_name = 'brokerage' THEN '2' 
      WHEN revenue_name = 'service fee' THEN '3' END AS id_retsuko_invoice_issuance,
  id_contract AS id_business_entity,
  id_invoice AS id_finance_entity,
  source_name,
  revenue_name,
  accrual_year_month,
  ABS(product_amount) AS source_amount,
  ABS(sap_amount) AS sap_amount,
  IF((ABS(product_amount) - ABS(sap_amount)) >= 0.05 OR (ABS(product_amount) - ABS(sap_amount)) <= -0.05 OR sap_amount IS NULL, FALSE, TRUE) AS is_compliance, 
  dt_source_created,
  dt_source_paid,
  dt_sap_created,
  dt_sap_reference
FROM 
  retsuko r
LEFT JOIN 
  sap s 
    ON r.id_invoice = s.id_finance_entity 
    AND r.revenue_name = s.revenue_account