WITH call_inapp_csat AS (
  SELECT
    COALESCE(
      GET_JSON_OBJECT(ev.metadata,"$.event_data.TaskAttributes.call_sid"),
      GET_JSON_OBJECT(ev.metadata,'$.event_data.TaskAttributes.callSid')
    ) AS id_call,
    CAST(GET_JSON_OBJECT(ev.metadata,"$.event_data.TaskAttributes.csat-1") AS INT) AS csat_1,
    CAST(GET_JSON_OBJECT(ev.metadata,"$.event_data.TaskAttributes.csat-2") AS INT) AS csat_2,
    CAST(GET_JSON_OBJECT(ev.metadata,"$.event_data.TaskAttributes.csat-3") AS INT) AS csat_3,
    TO_TIMESTAMP(FROM_UTC_TIMESTAMP(ev.event_timestamp, "Brazil/East"), "yyyy-MM-dd HH:mm:ss") AS ts_created_local,
    year,
    month,
    day
  FROM
    datalake_bigfone_clean.event AS ev
  WHERE
    (
      GET_JSON_OBJECT(metadata,"$.event_data.TaskAttributes.direction") = "outbound-api"
      OR GET_JSON_OBJECT(metadata,"$.event_data.TaskAttributes.channelType") = "call-in-app"
    )
    AND ev.year = {year}
    AND ev.month = {month}
    AND ev.day = {day}
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_call ORDER BY event_timestamp DESC) = 1
),
ivr_csat AS (
  SELECT
    id_call,
    csat_1,
    csat_2,
    csat_3,
    ts_created_local,
    year,
    month,
    day
  FROM
    datalake_bigfone_twilio.call_ivr_events
  WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
  QUALIFY
      ROW_NUMBER() OVER(PARTITION BY id_call ORDER BY ts_created_local DESC) = 1

),
csat_events AS (
  SELECT
    id_call,
    csat_1,
    csat_2,
    csat_3,
    ts_created_local,
    year,
    month,
    day
  FROM
    call_inapp_csat
  UNION ALL
  SELECT
    id_call,
    csat_1,
    csat_2,
    csat_3,
    ts_created_local,
    year,
    month,
    day
  FROM
    ivr_csat
),
call_csat AS (
  SELECT DISTINCT
    ce.id_call,
    ftm.id_contract,
    ftm.id_ticket,
    ftm.id_user_main AS id_user,
    ce.csat_1,
    ce.csat_2,
    ce.csat_3,
    CASE
      WHEN cs.direction = "outbound-api" OR cs.channel_type = "call-in-app" THEN "call inapp"
      ELSE "call"
    END AS service_context,
    ce.ts_created_local,
    ce.year,
    ce.month,
    ce.day
  FROM
    csat_events AS ce
  LEFT JOIN
    datalake_bigfone_twilio.call_flex_events AS cs
      ON ce.id_call = cs.id_call
      AND cs.year <= {year}
      AND cs.month <= {month}
      AND cs.day <= {day}
  LEFT JOIN
    datalake_zendesk.tickets_current ftm
      ON ce.id_call = ftm.id_call
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY ce.id_call ORDER BY ce.ts_created_local DESC) = 1
)
SELECT
    MD5(CONCAT(id_call, "csat1", ts_created_local)) AS id_answer,
    COALESCE(id_contract, -1) AS id_contract,
    id_ticket,
    COALESCE(id_user, -1) AS id_user,
    "customer support" AS service_type,
    service_context,
    "bigfone" AS source_name,
    CASE
        WHEN csat_1 = 2 THEN 5
        ELSE csat_1
    END AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    ts_created_local AS ts_submitted,
    year,
    month,
    day
FROM
    call_csat AS cc
WHERE
    csat_1 IS NOT NULL
UNION ALL
SELECT
    MD5(CONCAT(id_call, "csat2", ts_created_local)) AS id_answer,
    COALESCE(id_contract, -1) AS id_contract,
    id_ticket,
    COALESCE(id_user, -1) AS id_user,
    "customer support" AS service_type,
    service_context,
    "bigfone" AS source_name,
    csat_2 AS satisfaction_score,
    "resolution survey" AS score_description,
    ts_created_local AS ts_submitted,
    year,
    month,
    day
FROM
    call_csat AS cc
WHERE
    csat_2 IS NOT NULL
UNION ALL
SELECT
    MD5(CONCAT(id_call, "csat3", ts_created_local)) AS id_answer,
    COALESCE(id_contract, -1) AS id_contract,
    id_ticket,
    COALESCE(id_user, -1) AS id_user,
    "customer support" AS service_type,
    service_context,
    "bigfone" AS source_name,
    csat_3 AS satisfaction_score,
    CASE
      WHEN service_context = "call inapp" THEN "chatbot resolution evaluation"
      ELSE "ivr resolution evaluation"
    END AS score_description,
    ts_created_local AS ts_submitted,
    year,
    month,
    day
FROM
    call_csat AS cc
WHERE
    csat_3 IS NOT NULL
