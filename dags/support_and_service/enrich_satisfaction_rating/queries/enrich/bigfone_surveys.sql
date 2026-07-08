WITH call_sessions_raw AS (
    SELECT
        source_identity,
        public_id,
        ROW_NUMBER() OVER(PARTITION BY source_identity ORDER BY id) AS rn
    FROM
        datalake_support_session_service_clean.support_session
    WHERE
        source IN ('call', 'call_in_app')
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') - INTERVAL 30 DAY AND DATE('{load_end_date}')
),
call_sessions AS (
    SELECT
        source_identity,
        public_id
    FROM
        call_sessions_raw
    WHERE
        rn = 1
),
csat_events_raw AS (
    SELECT
      id_call,
      id_task,
      direction,
      channel_type,
      csat_1,
      csat_2,
      csat_3,
      ts_created - INTERVAL 3 HOUR AS ts_created_local,
      year,
      month,
      day,
      ROW_NUMBER() OVER(PARTITION BY id_call ORDER BY ts_created DESC) AS rn
    FROM
      datalake_bigfone_clean.event
    WHERE
      (
        csat_1 IS NOT NULL
        OR csat_2 IS NOT NULL
        OR csat_3 IS NOT NULL
      )
      AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
csat_events AS (
    SELECT
      id_call,
      id_task,
      direction,
      channel_type,
      csat_1,
      csat_2,
      csat_3,
      ts_created_local,
      year,
      month,
      day
    FROM
      csat_events_raw
    WHERE
      rn = 1
),
tickets_by_call_raw AS (
    SELECT
        id_call,
        CAST(id_contract AS BIGINT) AS id_contract,
        id_ticket,
        id_user_main,
        ROW_NUMBER() OVER(PARTITION BY id_call ORDER BY id_ticket DESC) AS rn
    FROM
        datalake_customer_support.tickets
    WHERE
        channel = 'call'
),
tickets_by_call AS (
    SELECT
        id_call,
        id_contract,
        id_ticket,
        id_user_main
    FROM
        tickets_by_call_raw
    WHERE
        rn = 1
),
call_csat AS (
    SELECT
      ce.id_call,
      cs.id_contract,
      cs.id_ticket,
      cs.id_user_main AS id_user,
      COALESCE(css_call.public_id, css_task.public_id) AS id_support_session,
      ce.csat_1,
      ce.csat_2,
      ce.csat_3,
      CASE
        WHEN ce.direction = "outbound-api" OR ce.channel_type = "call-in-app" THEN "call inapp"
        ELSE "call"
      END AS service_context,
      ce.ts_created_local,
      ce.year,
      ce.month,
      ce.day
    FROM
      csat_events AS ce
    LEFT JOIN
      call_sessions AS css_call
        ON css_call.source_identity = ce.id_call
    LEFT JOIN
      call_sessions AS css_task
        ON css_task.source_identity = ce.id_task
    LEFT JOIN
      tickets_by_call AS cs
        ON ce.id_call = cs.id_call
  )
  SELECT
      MD5(CONCAT(id_call, "csat1", ts_created_local)) AS id_answer,
      COALESCE(id_contract, -1) AS id_contract,
      id_ticket,
      COALESCE(id_user, -1) AS id_user,
      id_support_session,
      "customer support" AS service_type,
      service_context,
      "bigfone" AS source_name,
      csat_1 AS satisfaction_score,
      "resolution survey" AS score_description,
      CASE
        WHEN csat_1 = 1 THEN TRUE
        ELSE FALSE
      END AS is_solved,
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
      id_support_session,
      "customer support" AS service_type,
      service_context,
      "bigfone" AS source_name,
      csat_2 AS satisfaction_score,
      "satisfaction evaluation" AS score_description,
      NULL AS is_solved,
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
      id_support_session,
      "customer support" AS service_type,
      service_context,
      "bigfone" AS source_name,
      csat_3 AS satisfaction_score,
      CASE
        WHEN service_context = "call inapp" THEN "chatbot resolution evaluation"
        ELSE "ivr resolution evaluation"
      END AS score_description,
      NULL AS is_solved,
      ts_created_local AS ts_submitted,
      year,
      month,
      day
  FROM
      call_csat AS cc
  WHERE
      csat_3 IS NOT NULL
