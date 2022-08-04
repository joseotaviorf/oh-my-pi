SELECT
  id_visit AS sk_visit,
  email,
  visit_type,
  status,
  cancellation_reason_category,
  responsible,
  ts_visit,
  ts_visit_scheduling,
  ts_visit_cancellation
FROM
  datalake_money_laundering_prevention.visit