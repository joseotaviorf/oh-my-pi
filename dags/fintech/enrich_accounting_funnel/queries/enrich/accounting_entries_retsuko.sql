WITH retsuko_nf AS (
  SELECT DISTINCT
      i.id_external AS id_invoice,
      SPLIT(e.bill_item, 'entry.bill-item/')[1] AS bill_item,
      SUM(amount) AS total_bill_item
  FROM 
      datalake_retsuko.entry e
  INNER JOIN 
      datalake_retsuko.invoice i
          on e.id_invoice = i.id
  INNER JOIN
      datalake_retsuko.invoice_info ii 
          on ii.id_invoice = i.id_external
  INNER JOIN
      datalake_retsuko_clean.contract ct 
          on ct.id = i.id_contract
  WHERE 
      TRUE
  AND (
          (
              (ii.invoice_user = 'landlord') AND 
              (i.status != 'canceled') AND 
              (i.ts_due < current_date) AND
              (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                'adm-fee', 
                'brokerage-installment', 
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
              (i.status = 'paid') AND
              (i.ts_due < current_date) AND
              (SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
                'service-fee'
                )            
              )
          )
      )
  AND 
      i.accrual_year_month >= 202301
  AND 
      ct.country_code = 'BR'
  GROUP BY
      1, 2 
  HAVING 
    SUM(amount) != 0
),

retsuko_lcm AS (
  SELECT DISTINCT
      i.id_external AS id_invoice
  FROM 
      datalake_retsuko.entry e
  INNER JOIN 
      datalake_retsuko.invoice i
          on e.id_invoice = i.id
  INNER JOIN
      datalake_retsuko.invoice_info ii 
          on ii.id_invoice = i.id_external
  INNER JOIN
      datalake_retsuko_clean.contract ct 
          on ct.id = i.id_contract
  INNER JOIN 
      datalake_ebdb_clean.contract c 
          on c.id = ct.id_external
  WHERE 
      TRUE
  AND 
      e.amount != 0
  AND 
      NOT(
              SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
              'adm-fee-tax-pcc-adm-partner',
              'adm-fee-tax-pcc-quintoandar',
              'adm-fee-tax-ir-quinto-andar',
              'adm-fee-tax-ir',
              'adm-fee-tax-pcc',
              'adm-fee-tax-ir-adm-partner',
              'adm-fee-tax-pcc-quinto-andar',
              'brokerage-fee-tax-ir-adm-partner',
              'brokerage-fee-tax-ir',
              'brokerage-fee-tax-ir-quinto-andar',
              'brokerage-quinto-andar-postponed',
              'brokerage-installment',
              'condominium-5A-paid',
              'debit-negotiation',
              'residential-protection-5A-acquittance',
              'service-fee',
              'utilities-defaulting'
              )
            AND 
              i.status IN ('open', 'canceled')
      )
  AND 
      NOT(
              SPLIT(e.bill_item, 'entry.bill-item/')[1] IN (
              'iptu',
              'iptu-adjustment'
              )
            AND 
              c.paying_iptu = 'QuintoAndar'
      )
  AND 
      i.accrual_year_month >= 202301
  AND 
      ct.country_code = 'BR'
),

invoice_selected AS (
    SELECT DISTINCT 
        id_invoice
    FROM 
        retsuko_lcm 
    UNION
    SELECT DISTINCT
        id_invoice
    FROM 
        retsuko_nf
)

SELECT
  e.id_external AS id_invoice_entry,
  i.id_external AS id_invoice,
  ct.id_external AS id_contract,    
  sap.id_sap_gateway_feature,
  ii.invoice_user,
  ii.invoice_frequency,
  ii.payment_status,
  ii.substatus,
  ii.closing_mode,
  e.producer,
  i.paid_via,
  e.bill_item AS entry_type,
  e.description AS entry_description,
  e.amount AS entry_due_amount,
  i.due_amount AS invoice_due_amount,
  i.paid_amount AS invoice_paid_amount,
  IF(il.id_invoice IS NOT NULL, TRUE, FALSE) AS has_sap_lcm,
  IF(inf.id_invoice IS NOT NULL, TRUE, FALSE) AS has_sap_invoice,
  e.accrual_year_month AS entry_accrual,
  i.accrual_year_month AS invoice_accrual,
  CAST(e.ts_created AS DATE) AS dt_entry_created,
  CAST(i.ts_created AS DATE) AS dt_invoice_created,
  CAST(i.ts_due AS DATE) AS dt_invoice_due,
  CAST(i.ts_paid AS DATE) AS dt_invoice_paid
FROM 
    datalake_retsuko.entry e
INNER JOIN 
    datalake_retsuko.invoice i
        on e.id_invoice = i.id
INNER JOIN
    datalake_retsuko.invoice_info ii 
        on ii.id_invoice = i.id_external
INNER JOIN
    datalake_retsuko_clean.contract ct 
        on ct.id = i.id_contract
INNER JOIN 
    invoice_selected iss 
        on iss.id_invoice = i.id_external
LEFT JOIN 
    retsuko_lcm il
        on il.id_invoice = i.id_external
LEFT JOIN 
    retsuko_nf inf
        on inf.id_invoice = i.id_external
LEFT JOIN 
    datalake_retsuko_clean.sap_entity sap 
        on sap.id_finance_entity = i.id_external