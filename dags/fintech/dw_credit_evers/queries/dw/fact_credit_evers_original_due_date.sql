WITH debtors_all_time AS (
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
    ts_due
  FROM
    dw_credit_evers.fact_ever_invoices
  WHERE
    is_debt_forgiveness IS FALSE
    AND ts_signature >= DATE('2018-01-01')
    AND purpose IN ('monthly', 'onboarding')
    AND (paid_amount IS NULL
      OR status <> 'divergent-payment'
        OR (status LIKE 'divergent-payment'
          AND (paid_amount IS NOT NULL
            AND (due_amount + paid_amount)/due_amount < 0.01)))
),
debtors_agreement AS (
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
    ts_due
  FROM
    dw_credit_evers.fact_ever_invoices
  WHERE
    is_debt_forgiveness IS FALSE
    AND is_agreement = TRUE
    AND ts_signature >= DATE('2018-01-01')
    AND purpose IN ('monthly', 'onboarding')
    AND (paid_amount IS NULL
      OR status <> 'divergent-payment'
        OR (status LIKE 'divergent-payment'
          AND (paid_amount IS NOT NULL
            AND (due_amount + paid_amount)/due_amount < 0.01)))
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
    dt_contract_updated
FROM
    debtors_all_time
CROSS JOIN
    mob_array AS ma
CROSS JOIN
    ever_array AS ea
),
ever_rule_agreement AS (
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
    dt_contract_updated
FROM
    debtors_agreement
CROSS JOIN
    mob_array AS ma
CROSS JOIN
    ever_array AS ea
),
calculate_final_ever AS (
  SELECT
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    months_of_contract,
    contract_mob_number,
    contract_ever_number,
    MAX(IF(flag_ever = 1, max_invoice_mob, NULL)) AS invoice_anchor,
    MAX(max_invoice_mob) AS invoice_origin,
    CAST(MAX(flag_ever) AS BOOLEAN) AS is_ever,
    CAST(SUM(flag_ever) AS INTEGER) AS num_overs_in_mob_window,
    SUM(IF(flag_ever = 1, due_amount, 0)) AS total_due_amount_in_mob_window,
    CAST(SUM(IF(invoice_over_number >= contract_ever_number,1,0)) AS INTEGER) AS num_total_overs,
    SUM(IF(invoice_over_number >= contract_ever_number,due_amount,0)) AS total_due_amount,
    ts_signature,
    dt_reference,
    dt_contract_updated
FROM 
  ever_rule
GROUP BY 1,2,3,4,5,6,14,15,16
HAVING
  (is_ever = FALSE
  AND (months_of_contract > contract_mob_number)
  OR (is_ever = TRUE)
  )
),
calculate_final_agreement AS (
  SELECT
    id_contract_ebdb,
    id_contract_retsuko,
    id_proposal,
    months_of_contract,
    contract_mob_number,
    contract_ever_number,
    MAX(IF(flag_ever = 1, max_invoice_mob, NULL)) AS invoice_anchor,
    MAX(max_invoice_mob) AS invoice_origin,
    CAST(MAX(flag_ever) AS BOOLEAN) AS is_ever,
    CAST(SUM(flag_ever) AS INTEGER) AS num_overs_in_mob_window,
    SUM(IF(flag_ever = 1, due_amount, 0)) AS total_due_amount_in_mob_window,
    CAST(SUM(IF(invoice_over_number >= contract_ever_number,1,0)) AS INTEGER) AS num_total_overs,
    SUM(IF(invoice_over_number >= contract_ever_number,due_amount,0)) AS total_due_amount,
    ts_signature,
    dt_reference,
    dt_contract_updated,
    TRUE as is_agreement
FROM ever_rule_agreement
GROUP BY 1,2,3,4,5,6,14,15,16
HAVING
  (is_ever = FALSE
  AND (months_of_contract > contract_mob_number)
  OR (is_ever = TRUE)
  )
),
base_ever AS (
  SELECT 
  ev.*,
  IF(ag.is_agreement = TRUE, TRUE, FALSE) AS is_agreement
  FROM 
    calculate_final_ever ev
  LEFT JOIN 
    calculate_final_agreement ag
    ON ev.id_contract_ebdb = ag.id_contract_ebdb
    AND ev.contract_mob_number = ag.contract_mob_number
    AND ev.contract_ever_number = ag.contract_ever_number
  UNION ALL
  SELECT 
    *
  FROM 
    calculate_final_agreement
  WHERE 
    id_contract_ebdb NOT IN (SELECT id_contract_ebdb FROM calculate_final_ever)
),
dt_cancellation AS (
SELECT
  sk_negotiation,
  id_contract,
  dt_cancellation
FROM 
  dw_collection_recovery.fact_negotiation
WHERE 
  creditor = 'IQ QuintoAndar'
  AND is_down_payment_paid = TRUE
  AND negotiation_status IN ('broken','finished','offset')
  AND number_of_installments > 1
  AND promisse_payment_method <> 'CARTÃO'
QUALIFY row_number() 
  OVER ( PARTITION BY id_contract  ORDER BY CASE WHEN negotiation_status = 'broken' THEN 1 ELSE 0 END DESC,sk_negotiation ) = 1
)
SELECT
  b.id_contract_ebdb,
  b.id_contract_retsuko,
  b.id_proposal,
  b.invoice_anchor,
  b.invoice_origin,
  b.months_of_contract,
  b.contract_mob_number,
  b.contract_ever_number,
  b.num_overs_in_mob_window,
  b.total_due_amount_in_mob_window,
  b.num_total_overs,
  b.total_due_amount,
  b.is_ever,
  b.is_agreement,
  b.ts_signature,
  b.dt_reference,
  b.dt_contract_updated,
  c.dt_cancellation
FROM
  base_ever b
LEFT JOIN 
  dt_cancellation c
  ON b.id_contract_ebdb = c.id_contract
  AND b.is_agreement = TRUE
