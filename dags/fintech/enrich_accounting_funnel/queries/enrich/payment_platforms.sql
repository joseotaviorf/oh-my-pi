WITH trato_feito AS (
  SELECT DISTINCT
    CAST(i.id AS STRING) AS id_payment_platform,
    n.id_debtor_external AS id_business_entity,
    ai.id_external AS id_finance_entity,
    'trato-feito' AS payment_platform,
    p.status AS payment_status,
    CAST(p.metadata:paid_amount AS DOUBLE) AS paid_amount,
    CAST(SPLIT(p.metadata:paid_date, 'T')[0] AS DATE) AS dt_paid
  FROM 
    datalake_trato_feito_clean.negotiation n 
  INNER JOIN
    datalake_trato_feito_clean.installment i 
      ON n.id = i.id_negotiation
  INNER JOIN
    datalake_trato_feito_clean.accounting_installment ai 
      ON ai.id_installment = i.id
  LEFT JOIN 
    datalake_trato_feito_clean.payment p 
      ON p.id_installment = i.id
),

wallstreet AS (
  SELECT DISTINCT
    CAST(id as STRING) as id_payment_platform,
    c.id_business_entity,
    id_finance_entity,
    'wallstreet' as payment_platform,
    charge_status as payment_status,
    CAST(amount/100.00 AS DOUBLE) as paid_amount,
    CAST(c.ts_paid AS DATE) as dt_paid
  FROM  
    datalake_wall_street_clean.charge c
  QUALIFY
    RANK() OVER (PARTITION BY c.id_finance_entity ORDER BY c.ts_updated DESC) = 1
),

robin_hood AS (
  SELECT DISTINCT
    CAST(ae.id AS STRING) AS id_payment_platform,
    NULL AS id_business_entity,
    ae.id_external AS id_finance_entity,
    'robin-hood' AS payment_platform,
    pr.status AS payment_status,
    ae.due_amount AS paid_amount,
    pr.dt_paid
  FROM 
    datalake_robin_hood.accounting_entry ae
  LEFT JOIN 
    datalake_robin_hood_clean.accounting_entry_balance eb 
      ON eb.id_accounting_entry = ae.id
  LEFT JOIN 
    datalake_robin_hood_clean.payment_request pr 
      ON pr.id = eb.id_payment_request
  WHERE 
    source_bill_item = 'estate-agent-services'
  QUALIFY
    RANK() OVER (PARTITION BY ae.id_external ORDER BY pr.ts_created DESC) = 1
),

vans AS (
WITH boleto_file_response AS (    
  SELECT
    id
  FROM 
    datalake_vans_clean.file f 
  WHERE 
    f.type =':file.type/boleto'
  AND f.origin = ':file.origin/response'
)

SELECT DISTINCT
  CAST(p.id AS STRING) AS id_payment_platform,
  SPLIT(p.company_use, '[a-zA-Z]')[0] AS id_business_entity,
  p.id_related_document AS id_finance_entity,
  'vans' AS payment_platform,
  SPLIT(p.status, "/")[1] AS payment_status,
  p.paid_amount AS payment_amount,
  p.dt_paid
FROM 
  datalake_vans_clean.payment p
WHERE 
  p.id_related_document IS NOT NULL
QUALIFY
  RANK() OVER (PARTITION BY p.id_related_document ORDER BY ts_updated DESC) = 1

UNION ALL

SELECT
  CAST(b.id AS STRING) as id_payment_platform,
  SPLIT(b.company_use, '[a-zA-Z]')[0] AS id_business_entity,
  b.id_related_document AS id_finance_entity,
  'vans' AS payment_platform, 
  SPLIT(b.status, "/")[1] AS payment_status, 
  b.paid_amount AS payment_amount,
  b.dt_paid
FROM 
  datalake_vans_clean.boleto b
INNER JOIN
  datalake_vans_clean.boleto_file bf
    ON b.id = bf.id_boleto 
INNER JOIN
  boleto_file_response bfr
    ON bfr.id = bf.id_file
WHERE
  b.id_related_document IS NOT NULL
QUALIFY
  RANK() OVER (PARTITION BY b.id_related_document ORDER BY b.ts_updated DESC) = 1
)

SELECT 
  * 
FROM 
  trato_feito
UNION ALL
SELECT 
  * 
FROM 
  wallstreet
UNION ALL 
SELECT 
  * 
FROM 
  robin_hood
UNION ALL
SELECT 
  * 
FROM 
  vans