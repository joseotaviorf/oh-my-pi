SELECT
  CAST(id_ticket AS BIGINT) AS sk_ticket,
  channel,
  csat_comment,
  source,
  resolution_survey,
  csat_score,
  ts_survey,
  ts_response
FROM
  datalake_customer_support.csat