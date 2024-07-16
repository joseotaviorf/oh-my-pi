WITH csat_events AS (
    SELECT
      id_call,
      direction,
      channel_type,
      csat_1,
      csat_2,
      csat_3,
      ts_created - INTERVAL 3 HOUR AS ts_created_local,
      year,
      month,
      day
    FROM
      datalake_bigfone_clean.event
    WHERE
      (
        csat_1 IS NOT NULL
        OR csat_2 IS NOT NULL
        OR csat_3 IS NOT NULL
      )
      AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_call ORDER BY ts_created DESC) = 1

  ),
  call_csat AS (
    SELECT DISTINCT
      ce.id_call,
      CAST(cs.id_contract AS BIGINT) AS id_contract,
      cs.id_ticket,
      cs.id_user,
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
      datalake_customer_support.call AS cs
        ON ce.id_call = cs.id_call
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
