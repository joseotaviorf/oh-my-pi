WITH dispatch_explode AS (
  SELECT
      id,
      EXPLODE(FROM_JSON(customers,'array<string>')) AS customers_explode,
      ts_created,
      DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_updated
  FROM
      datalake_tracksale_clean.dispatch
)
SELECT DISTINCT
  id,
  GET_JSON_OBJECT(d.customers_explode,'$.name') as name,
  GET_JSON_OBJECT(d.customers_explode,'$.identification') as identification,
  GET_JSON_OBJECT(d.customers_explode,'$.email') as email,
  GET_JSON_OBJECT(d.customers_explode,'$.phone') as phone,
  GET_JSON_OBJECT(d.customers_explode,'$.status') as status,
  GET_JSON_OBJECT(d.customers_explode,'$.has_answered') as has_answered,
  GET_JSON_OBJECT(d.customers_explode,'$.survey_opened') as survey_opened,
  FROM_UTC_TIMESTAMP(FROM_UNIXTIME(GET_JSON_OBJECT(d.customers_explode,'$.dispatch_time'),"yyyy-MM-dd hh:mm:ss"),"America/Brasilia") as dispatch_time,
  ts_created,
  dt_updated
FROM
  dispatch_explode d

