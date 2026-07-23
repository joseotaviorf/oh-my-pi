WITH dispatch_explode AS (
  SELECT
    id,
    EXPLODE(FROM_JSON(customers, 'array<string>')) AS customers_explode,
    ts_created,
    CAST(CONCAT(CAST(year AS STRING), '-', CAST(month AS STRING), '-', CAST(day AS STRING)) AS DATE) AS dt_updated
  FROM datalake_tracksale_clean.dispatch
)
SELECT DISTINCT
  id,
  GET_JSON_OBJECT(d.customers_explode, name) AS name,
  GET_JSON_OBJECT(d.customers_explode, identification) AS identification,
  LOWER(GET_JSON_OBJECT(d.customers_explode, email)) AS email,
  GET_JSON_OBJECT(d.customers_explode, phone) AS phone,
  GET_JSON_OBJECT(d.customers_explode, status) AS status,
  GET_JSON_OBJECT(d.customers_explode, has_answered) AS has_answered,
  GET_JSON_OBJECT(d.customers_explode, survey_opened) AS survey_opened,
  FROM_UTC_TIMESTAMP(
    CAST(FROM_UNIXTIME(GET_JSON_OBJECT(d.customers_explode, dispatch_time), 'yyyy-MM-dd hh:mm:ss') AS TIMESTAMP),
    'America/Sao_Paulo'
  ) AS dispatch_time,
  ts_created,
  dt_updated
FROM dispatch_explode AS d
