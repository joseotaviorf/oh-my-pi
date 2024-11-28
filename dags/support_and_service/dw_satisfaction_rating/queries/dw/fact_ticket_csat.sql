SELECT
  CAST(id_ticket AS BIGINT) AS sk_ticket,
  first_csat_score,
  last_csat_score,
  first_csat_comment,
  last_csat_comment,
  is_answered,
  is_solved
  ts_first_responde,
  ts_last_response
FROM
  datalake_customer_support.csat
WHERE
  ts_first_response BETWEEN '{load_start_date}' AND '{load_end_date}'
