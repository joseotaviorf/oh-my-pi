SELECT
  id_ticket AS sk_ticket,
  channel,
  csat_comment,
  is_solved,
  csat_score,
  ts_survey,
  ts_response
FROM
  datalake_customer_support.csat