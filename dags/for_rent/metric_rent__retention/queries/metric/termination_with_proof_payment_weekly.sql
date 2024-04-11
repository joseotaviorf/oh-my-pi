WITH tenant_pending_tasks AS (
  SELECT
    fct.sk_contract,
    dc.value_segment,
    dt.send_utility_bills_receipt,
    dt.attachment_type_list,
    dt.dt_ended_termination
  FROM
    dw_retention.fact_contract_termination AS fct
  JOIN
    dw_retention.dim_termination AS dt
      ON fct.sk_termination = dt.sk_termination
  JOIN
    dw_rent.dim_contract AS dc
      ON fct.sk_contract = dc.sk_contract
  WHERE
    DATE_TRUNC('MONTH', dt.dt_ended_termination) >= DATE_TRUNC('MONTH', CURRENT_DATE() - INTERVAL '12' MONTH)
    AND dt.category != 'BEFORE_RENTAL'
),
metrics_calculation AS (
  SELECT
    DATE_TRUNC('WEEK', dt_ended_termination) AS dt_ended_termination_week,
    value_segment,
    COUNT(sk_contract) AS terminations,
    COUNT(IF(send_utility_bills_receipt = 'COMPLETED' AND (ARRAY_CONTAINS(attachment_type_list, 'CONDO_VOUCHER') OR ARRAY_CONTAINS(attachment_type_list, 'PAYMENT_VOUCHER')), sk_contract, NULL)) AS terminations_paid
  FROM
    tenant_pending_tasks
  GROUP BY
    1, 2
)
SELECT
  dt_ended_termination_week,
  value_segment AS category,
  terminations,
  terminations_paid,
  terminations_paid/terminations AS percentage_terminations_paid
FROM
  metrics_calculation
UNION ALL
SELECT
  dt_ended_termination_week,
  'OVERALL' AS category,
  SUM(terminations) AS terminations,
  SUM(terminations_paid) AS terminations_paid,
  SUM(terminations_paid)/SUM(terminations) AS percentage_terminations_paid
FROM
  metrics_calculation
GROUP BY
  1