WITH BaseAcordos AS (
  SELECT
    c.id_external AS NuContrato,
    n.id AS Id_Acordo,
    n.id_collector_external,
    n.status AS Status_Acordo,
    cast(n.ts_created AS date) AS Dt_Criacao_Acordo,
    d.id_external AS Invoice_id_Origem,
    cast(i.ts_due AS date) AS tsdue_Origem,
    i.due_amount AS dueAmount_Origem,
    cast(i.ts_paid AS date) AS tspaid_Origem,
    i.paid_amount
  FROM
    datalake_trato_feito_clean.negotiation AS n 
    INNER JOIN 
      datalake_trato_feito_clean.debt AS d 
        ON n.id = d.id_negotiation
    INNER JOIN 
      datalake_retsuko.invoice AS i
        ON i.id_external = d.id_external
    INNER JOIN 
      datalake_retsuko_clean.contract c  
  	    ON i.id_contract = c.id 
  WHERE
    n.ts_created <= current_date - interval '1' day
),
parcelas AS (
  SELECT
    a.NuContrato,
    a.Invoice_id_Origem,
    a.Id_Acordo,
    a.id_collector_external,
    a.tsdue_Origem,
    a.Dt_Criacao_Acordo,
    ai.id_external AS Invoice_id_acordo,
    cast(i.ts_due AS date) AS tsdue_Acordo,
    i.due_amount AS dueAmount_Acordo,
    cast(i.ts_paid AS date) AS tspaid_Acordo,
    i.paid_amount AS paidAmount_Acordo  
  FROM
    BaseAcordos AS a 
    INNER JOIN 
      datalake_trato_feito_clean.installment AS p
        ON a.Id_Acordo = p.id_negotiation
    INNER JOIN 
      datalake_trato_feito_clean.accounting_installment AS ai
        ON ai.id_installment = p.id
    INNER JOIN 
      datalake_retsuko.invoice AS i
        ON i.id_external = ai.id_external
),
min_invoice AS (
  SELECT
    id_acordo,
    min(tsdue_Origem) AS min_negociada
  FROM 
    BaseAcordos    
  GROUP BY 1 
),
total_negociado AS(  
  SELECT  
    NuContrato,
    Id_Acordo,
    id_collector_external,
    Invoice_id_Origem,
    tsdue_Origem,
    Dt_Criacao_Acordo,
    Sum(dueAmount_Acordo*(-1)) AS saldo_negociado,
    SUM(paidAmount_Acordo) AS vl_pago
  FROM  
    parcelas
  GROUP BY 1,2,3,4,5,6
)
SELECT 
  a.id_acordo as id_agreement,
  a.id_collector_external,
  CASE 
    WHEN datediff(day,c.min_negociada,b.Dt_Criacao_Acordo) IS null THEN null
    WHEN datediff(day,c.min_negociada,b.Dt_Criacao_Acordo) <= 0 THEN 'a. Current'
    WHEN datediff(day,c.min_negociada,b.Dt_Criacao_Acordo) <= 30 THEN 'b. 1-30'
    WHEN datediff(day,c.min_negociada,b.Dt_Criacao_Acordo) <= 60 THEN 'c. 31-60'
    WHEN datediff(day,c.min_negociada,b.Dt_Criacao_Acordo) <= 90 THEN 'd. 61-90'
    WHEN datediff(day,c.min_negociada,b.Dt_Criacao_Acordo) <= 180 THEN 'e. 91-180'
    ELSE 'f. acima de 180' 
  END AS delay_contamined_range,
  sum(dueAmount_Origem*(-1)) - max(b.saldo_negociado) AS discount,
  sum(dueAmount_Origem*(-1)) AS invoice_amount,
  a.nucontrato as contract_number,
  max(b.saldo_negociado) AS negotiation_amount,
  b.Dt_Criacao_Acordo AS dt_agreement_creation
FROM 
  BaseAcordos AS a
  LEFT JOIN 
    total_negociado AS b 
      ON a.Invoice_id_Origem = b.Invoice_id_Origem AND a.Id_Acordo = b.Id_Acordo
  LEFT JOIN 
    min_invoice AS c 
      ON a.id_acordo = c.id_acordo 
WHERE 
  a.Status_Acordo IN ('broken','finished','offset')
GROUP BY 1,2,3,6,8