WITH tenant_pending_tasks AS (
  SELECT
    fct.sk_contract,
    dt.send_utility_bills_receipt,
    dt.attachment_type_list,
    dt.dt_ended_termination
  FROM
    dw_retention.fact_contract_termination AS fct
  JOIN
    dw_retention.dim_termination AS dt
      ON fct.sk_termination = dt.sk_termination
  WHERE
    DATE_TRUNC('MONTH', dt.dt_ended_termination) >= DATE_TRUNC('MONTH', CURRENT_DATE() - INTERVAL '12' MONTH)
    AND dt.category != 'BEFORE_RENTAL'
),
metrics_calculation AS (
  SELECT
    DATE_TRUNC('WEEK', dt_ended_termination) AS dt_ended_termination_week,
    COUNT(sk_contract) AS terminations,
    COUNT(IF(send_utility_bills_receipt = 'COMPLETED' AND (ARRAY_CONTAINS(attachment_type_list, 'CONDO_VOUCHER') OR ARRAY_CONTAINS(attachment_type_list, 'PAYMENT_VOUCHER')), sk_contract, NULL)) AS sent_proof
  FROM
    tenant_pending_tasks
  GROUP BY 1
)
SELECT
  dt_ended_termination_week,
  terminations,
  sent_proof,
  sent_proof/terminations AS percentage_sent_proof
FROM
  metrics_calculation
