WITH pre_bot_actions AS (
  SELECT DISTINCT
    id_session,
    GET_JSON_OBJECT(input, '$.user_context.user_pre_bot_actions') AS user_pre_bot_actions,
    TRANSFORM(
      FROM_JSON(GET_JSON_OBJECT(input, '$.user_context.user_pre_bot_actions'), 'array<string>'),
      x -> FROM_JSON(
        x,
        'struct<title:string,message:string,rule_order:int,worker:string,department:string,ticket_id:string,type:string>'
      )
    ) AS arr_pre_bot,
    ts_created
  FROM datalake_langfuse_clean.traces
  WHERE
    ts_created >= CAST('{load_start_date}' AS DATE)
    AND GET_JSON_OBJECT(input, '$.user_context.user_pre_bot_actions') <> '[]'
    AND NOT GET_JSON_OBJECT(input, '$.user_context.user_pre_bot_actions') IS NULL
), bypasses AS (
  SELECT
    id_session,
    EXPLODE(arr_pre_bot) AS bypass,
    ts_created
  FROM pre_bot_actions
), inside_sales_bypass AS (
  SELECT
    t.id_session,
    MIN(t.ts_created) AS ts_created
  FROM datalake_langfuse_clean.traces AS t
  INNER JOIN datalake_langfuse_clean.observations AS o
    ON o.id_trace = t.id_trace
    AND o.ts_started >= CAST('{load_start_date}' AS DATE)
    AND GET_JSON_OBJECT(o.output, should_route) = 'true'
  WHERE
    t.ts_created >= CAST('{load_start_date}' AS DATE)
  GROUP BY
    1
)
SELECT
  id_session AS id_langfuse_session,
  bypass.title AS bypass,
  bypass.type AS type,
  bypass.ticket_id AS id_ticket,
  bypass.department AS queue,
  ts_created
FROM bypasses
UNION ALL
SELECT
  id_session AS id_langfuse_session,
  'inside_sales_bypass' AS bypass,
  NULL AS type,
  NULL AS id_ticket,
  NULL AS queue,
  ts_created
FROM inside_sales_bypass