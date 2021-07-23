WITH total_csat AS (
  SELECT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
    channel,
    csat_comment,
    source,
    resolution_survey,
    csat_score,
    ts_survey,
    ts_response,
    row_number() OVER(PARTITION BY id_ticket ORDER BY ts_response) AS rowcount
  FROM
    datalake_customer_support.csat
)
SELECT 
  sk_ticket,
  channel,
  csat_comment,
  source,
  resolution_survey,
  csat_score,
  ts_survey,
  ts_response
FROM
  total_csat
WHERE
  rowcount = 1
