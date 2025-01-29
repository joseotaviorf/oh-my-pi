WITH csat_zendesk AS (
  SELECT
    id_ticket,
    GET_JSON_OBJECT(satisfaction_rating, '$.comment') AS csat_comment,
    CASE
      WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') = 'bad' THEN  1
      WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') = 'good' THEN  5
      ELSE NULL
    END AS csat_score,
    GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('good', 'bad') AS is_answered,
    CASE
        WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('good') THEN TRUE
        WHEN GET_JSON_OBJECT(satisfaction_rating, '$.score') IN ('bad') THEN FALSE
    END AS is_solved,
    ts_updated AS ts_response
  FROM
    datalake_zendesk_clean.tickets
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' - INTERVAL 30 DAY AND '{load_end_date}'
    AND ts_updated >= '{load_start_date}' - INTERVAL 30 DAY
  UNION ALL
  SELECT
    id_ticket,
    user_comment AS csat_comment,
    csat_score,
    COALESCE(CAST(user_comment AS STRING), CAST(csat_score AS STRING), CAST(is_solved AS STRING)) IS NOT NULL AS is_answered,
    is_solved,
    ts_first_response AS ts_response
  FROM
    datalake_survicate.zendesk_email_surveys
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' - INTERVAL 30 DAY AND '{load_end_date}'
    AND ts_first_response >= '{load_start_date}' - INTERVAL 30 DAY
    AND id_ticket IS NOT NULL
    AND COALESCE(CAST(user_comment AS STRING), CAST(csat_score AS STRING), CAST(is_solved AS STRING)) IS NOT NULL
)
SELECT DISTINCT
  id_ticket,
  FIRST(csat_score) OVER(PARTITION BY id_ticket ORDER BY ts_response) AS first_csat_score,
  FIRST(csat_score) OVER(PARTITION BY id_ticket ORDER BY ts_response DESC) AS last_csat_score,
  FIRST(csat_comment) OVER(PARTITION BY id_ticket ORDER BY ts_response) AS first_csat_comment,
  FIRST(csat_comment) OVER(PARTITION BY id_ticket ORDER BY ts_response DESC) AS last_csat_comment,
  is_answered,
  MAX(is_solved) OVER(PARTITION BY id_ticket) AS is_solved,
  MIN(ts_response) OVER(PARTITION BY id_ticket) AS ts_first_response,
  MAX(ts_response) OVER(PARTITION BY id_ticket) AS ts_last_response
FROM
  csat_zendesk
WHERE
  csat_score IS NOT NULL
UNION ALL
SELECT DISTINCT
  t.id_ticket,
  FIRST(e.csat_2) OVER(PARTITION BY t.id_ticket ORDER BY e.ts_created) AS first_csat_score,
  FIRST(e.csat_2) OVER(PARTITION BY t.id_ticket ORDER BY e.ts_created DESC) AS last_csat_score,
  NULL AS first_csat_comment,
  NULL AS last_csat_comment,
  TRUE AS is_answered,
  e.csat_1 = 1 AS is_solved,
  MIN(e.ts_created) OVER(PARTITION BY t.id_ticket) AS ts_first_response,
  MAX(e.ts_created) OVER(PARTITION BY t.id_ticket) AS ts_last_response
FROM
  datalake_bigfone_clean.event AS e
LEFT JOIN
  datalake_customer_support.tickets AS t
    ON t.id_twilio = e.id_task
    OR t.id_twilio = e.id_call
WHERE
  MAKE_DATE(e.year, e.month, e.day) BETWEEN '{load_start_date}' - INTERVAL 30 DAY AND '{load_end_date}'
  AND e.csat_2 is not null
UNION ALL
SELECT DISTINCT
  c.id_ticket,
  FIRST(sa.rating) OVER(PARTITION BY c.id_ticket ORDER BY sa.ts_created) AS first_csat_score,
  FIRST(sa.rating) OVER(PARTITION BY c.id_ticket ORDER BY sa.ts_created DESC) AS last_csat_score,
  FIRST(NULLIF(sa.comment, '')) OVER(PARTITION BY id_ticket ORDER BY sa.ts_created) AS first_csat_comment,
  FIRST(NULLIF(sa.comment, '')) OVER(PARTITION BY id_ticket ORDER BY sa.ts_created DESC) AS last_csat_comment,
  TRUE AS is_answered,
  sa.is_solved,
  MIN(sa.ts_created) OVER(PARTITION BY c.id_ticket) AS ts_first_response,
  MAX(sa.ts_created) OVER(PARTITION BY c.id_ticket) AS ts_last_response
FROM
  datalake_chat_fup_clean.chats_chat AS c
INNER JOIN
  datalake_chat_fup_clean.surveys_survey AS ss
    ON ss.id_chat = c.id
LEFT JOIN
  datalake_chat_fup_clean.surveys_answer AS sa
    ON ss.id = sa.id_survey
WHERE
  sa.id IS NOT NULL
  AND DATE(c.ts_attended) BETWEEN '{load_start_date}' - INTERVAL 30 DAY AND '{load_end_date}'
  AND sa.rating IS NOT NULL
