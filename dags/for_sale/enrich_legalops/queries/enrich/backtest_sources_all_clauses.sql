SELECT
  cc.id AS ccv_clause_id,
  cc.id_sales_flow,
  cs.description AS clause_description,
  cc.variables AS clause_variables,
  cm.payment_method AS clause_payment_method,
  cm.title AS clause_title,
  cm.is_negotiation_clause,
  cm.clause_identifier,
  cm.id AS clause_message_id
FROM
  datalake_legalops.backtest_sources_sales_flows_screenings AS screening
LEFT JOIN
  datalake_sales_flow_clean.ccv_clause AS cc
    ON screening.id_sales_flow = cc.id_sales_flow
JOIN
  datalake_sales_flow_clean.clause_message AS cm
    ON cm.id = cc.id_message_clause
LEFT JOIN
  datalake_sales_flow_clean.clause_subject AS cs
    ON cm.id_subject = cs.id
WHERE
  cm.title IS NOT NULL
