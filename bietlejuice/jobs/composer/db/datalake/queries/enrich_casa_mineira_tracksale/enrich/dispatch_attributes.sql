WITH dispatch_explode AS (
  SELECT
      id,
      EXPLODE(FROM_JSON(customers,'array<string>')) AS customers_explode,
      ts_created,
      DATE(CONCAT(CAST(year AS VARCHAR(4)), '-', CAST(month AS VARCHAR(2)), '-', CAST(day AS VARCHAR(2)))) AS dt_updated
  FROM
      datalake_casa_mineira_tracksale_clean.dispatch
)
SELECT DISTINCT
  id,
  GET_JSON_OBJECT(d.customers_explode,'$.name') AS name,
  GET_JSON_OBJECT(d.customers_explode,'$.identification') AS identification,
  LOWER(GET_JSON_OBJECT(d.customers_explode,'$.email')) AS email,
  GET_JSON_OBJECT(d.customers_explode,'$.phone') AS phone,
  GET_JSON_OBJECT(d.customers_explode,'$.status') AS status,
  GET_JSON_OBJECT(d.customers_explode,'$.has_answered') AS has_answered,
  GET_JSON_OBJECT(d.customers_explode,'$.survey_opened') AS survey_opened,
  FROM_UTC_TIMESTAMP(FROM_UNIXTIME(GET_JSON_OBJECT(d.customers_explode,'$.dispatch_time'),"yyyy-MM-dd hh:mm:ss"),"America/Brasilia") AS dispatch_time,
  ts_created,
  dt_updated
FROM
  dispatch_explode d
