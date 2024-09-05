WITH debtors_agreement_base as (
select
  i.id_external AS id_invoice,
  CAST(NULL AS INTEGER) AS id_contract_ebdb,
  fn.id_contract AS id_contract_retsuko,
  flrf.sk_proposal AS id_proposal,
  MONTHS_BETWEEN(
  DATE_ADD(
    LAST_DAY(
      ADD_MONTHS(CURRENT_DATE(), -1)), 1
  ),
  DATE_ADD(
    LAST_DAY(
      ADD_MONTHS(c.ts_signature,-1)), 1
  )
) AS months_of_contract,
  CASE 
    WHEN DATEDIFF(dt_due_invoice_anchor, (c.ts_signature :: DATE)) <= 15 THEN 15 -- CURRENT DATE ?
    WHEN DATEDIFF(dt_due_invoice_anchor, (c.ts_signature :: DATE)) <= 30 THEN 30
    WHEN DATEDIFF(dt_due_invoice_anchor, (c.ts_signature :: DATE)) <= 40 THEN 40
    WHEN DATEDIFF(dt_due_invoice_anchor, (c.ts_signature :: DATE)) <= 60 THEN 60
    WHEN DATEDIFF(dt_due_invoice_anchor, (c.ts_signature :: DATE)) <= 90 THEN 90
    ELSE 120
  END AS invoice_over_number,
  i.due_amount,
  DATE_ADD(
      ADD_MONTHS(DATE_FORMAT(CAST(UNIX_TIMESTAMP(CONCAT(
        CAST(i.accrual_year_month AS STRING),
      '01'),'yyyyMMdd')AS TIMESTAMP), 'yyyy-MM-dd'),1),6) 
  AS original_due_date,
  CAST(NULL AS DATE) AS dt_contract_updated,
  c.ts_signature,
  i.ts_due,
  TRUE AS is_agreement,
  id_collector_external,
  fn.sk_negotiation
FROM 
  datalake_trato_feito_clean.negotiation n 
INNER JOIN 
  datalake_trato_feito_clean.debt d
  ON n.id = d.id_negotiation
INNER JOIN 
  datalake_retsuko.invoice i
  ON i.id_external = d.id_external
INNER JOIN 
  datalake_retsuko_clean.contract c  
	ON i.id_contract = c.id
LEFT JOIN
  dw_collection_recovery.fact_negotiation fn
  ON fn.sk_negotiation = n.id_collector_external
LEFT JOIN 
  dw_rent.fact_listing_rent_flows flrf
  ON fn.id_contract = flrf.sk_contract
WHERE
      n.status in ('offset','broken','finished')
  AND i.purpose in ('monthly','onboarding')
  AND fn.creditor = 'IQ QuintoAndar'
  AND fn.is_down_payment_paid = true
  AND fn.negotiation_status = 'broken'
  AND fn.number_of_installments > 1
  AND fn.promisse_payment_method <> 'CARTÃO' 
),
debtor_agreement AS (
SELECT 
  id_invoice,
  id_contract_ebdb,
  id_contract_retsuko,
  id_proposal,
  months_of_contract,
  invoice_over_number,
  due_amount,
  original_due_date,
  dt_contract_updated,
  ts_signature,
  ts_due,
  is_agreement
FROM
  debtors_agreement_base
QUALIFY 
  ROW_NUMBER() OVER (PARTITION BY id_contract_retsuko  ORDER BY sk_negotiation ) = 1 
),
debtors_all_time AS (
  SELECT
    id_invoice,
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    MONTHS_BETWEEN(
      DATE_ADD(
        LAST_DAY(
          ADD_MONTHS(CURRENT_DATE(), -1)), 1
      ),
      DATE_ADD(
        LAST_DAY(
          ADD_MONTHS(ts_signature,-1)), 1
      )
    ) AS months_of_contract,
    CASE
      WHEN is_over_120 THEN 120
      WHEN is_over_90 THEN 90
      WHEN is_over_60 THEN 60
      WHEN is_over_40 THEN 40
      WHEN is_over_30 THEN 30
      WHEN is_over_15 THEN 15
    END AS invoice_over_number,
    due_amount,
    original_due_date,
    dt_contract_updated,
    ts_signature,
    ts_due,
    FALSE AS is_agreement
  FROM
    datalake_invoice.credit_invoice_original_due_date
  WHERE
    is_debt_forgiveness IS FALSE
    AND ts_signature >= DATE('2018-01-01')
    AND purpose IN ('monthly', 'onboarding')
    AND (paid_amount IS NULL
      OR status <> 'divergent-payment'
        OR (status LIKE 'divergent-payment'
          AND (paid_amount IS NOT NULL
            AND (due_amount + paid_amount)/due_amount < 0.01)))
UNION ALL
SELECT
  id_invoice,
  id_contract_ebdb,
  id_contract_retsuko,
  id_proposal,
  months_of_contract,
  invoice_over_number,
  due_amount,
  original_due_date,
  dt_contract_updated,
  ts_signature,
  ts_due,
  is_agreement
FROM 
  debtor_agreement
),
mob_array AS (
  SELECT
    EXPLODE(
      ARRAY(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 30, 40)
    ) AS contract_mob_number
),
ever_array AS (
  SELECT
    EXPLODE(
      ARRAY(15, 30, 40, 60, 90, 120)
    ) AS contract_ever_number
),
ever_rule AS (
SELECT
    id_invoice,
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    CAST(months_of_contract AS INTEGER) AS months_of_contract,
    ma.contract_mob_number,
    ea.contract_ever_number,
    CASE
          WHEN invoice_over_number >= ea.contract_ever_number
            AND (12*(DATE_FORMAT(DATE_ADD(original_due_date, ea.contract_ever_number), "y") - DATE_FORMAT(ts_signature, "y")) +
                      (DATE_FORMAT(DATE_ADD(original_due_date, ea.contract_ever_number), "M")-DATE_FORMAT(ts_signature, "M"))) <= ma.contract_mob_number THEN 1
          ELSE 0
        END AS flag_ever,
    invoice_over_number,
    FIRST_VALUE(id_invoice) OVER(PARTITION BY id_contract_ebdb, id_proposal ORDER BY invoice_over_number DESC,original_due_date ASC) AS max_invoice_mob,
    due_amount,
    ts_signature,
    DATE_ADD(ts_signature,INT(contract_mob_number)) AS dt_reference,
    dt_contract_updated,
    is_agreement
FROM
    debtors_all_time
CROSS JOIN
    mob_array AS ma
CROSS JOIN
    ever_array AS ea
)
SELECT
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    months_of_contract,
    contract_mob_number,
    contract_ever_number,
    MAX(IF(flag_ever = 1, max_invoice_mob, NULL)) AS invoice_anchor,
    CAST(MAX(flag_ever) AS BOOLEAN) AS is_ever,
    is_agreement,
    CAST(SUM(flag_ever) AS INTEGER) AS num_overs_in_mob_window,
    SUM(IF(flag_ever = 1, due_amount, 0)) AS total_due_amount_in_mob_window,
    CAST(SUM(IF(invoice_over_number >= contract_ever_number,1,0)) AS INTEGER) AS num_total_overs,
    SUM(IF(invoice_over_number >= contract_ever_number,due_amount,0)) AS total_due_amount,
    ts_signature,
    dt_reference,
    dt_contract_updated
FROM ever_rule
GROUP BY
    1,2,3,4,5,6,9,14,15,16
HAVING
    (is_ever = FALSE
        AND (months_of_contract > contract_mob_number)
            OR (is_ever = TRUE)
            )
