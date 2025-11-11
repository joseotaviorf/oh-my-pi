WITH csat_zendesk AS (
  SELECT
    id_ticket,
    'zendesk' AS source,
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
    year >= YEAR(DATE('{load_start_date}') - INTERVAL 3 YEAR)
    AND GET_JSON_OBJECT(satisfaction_rating, '$.score') IS NOT NULL
  UNION ALL
  SELECT
    id_ticket,
    'survicate' AS source,
    user_comment AS csat_comment,
    csat_score,
    COALESCE(CAST(user_comment AS STRING), CAST(csat_score AS STRING), CAST(is_solved AS STRING)) IS NOT NULL AS is_answered,
    is_solved,
    ts_first_response AS ts_response
  FROM
    datalake_survicate.zendesk_email_surveys
  WHERE
    year >= YEAR(DATE('{load_start_date}') - INTERVAL 3 YEAR)
    AND id_ticket IS NOT NULL
    AND COALESCE(CAST(user_comment AS STRING), CAST(csat_score AS STRING), CAST(is_solved AS STRING)) IS NOT NULL
),
csat AS (
  SELECT DISTINCT
    id_ticket,
    source,
    csat_score,
    csat_comment,
    is_answered,
    is_solved,
    ts_response
  FROM
    csat_zendesk
  WHERE
    csat_score IS NOT NULL
  UNION ALL
  SELECT DISTINCT
    t.id_ticket,
    'bigfone' AS source,
    e.csat_2 AS csat_score,
    NULL AS csat_comment,
    TRUE AS is_answered,
    e.csat_1 = 1 AS is_solved,
    e.ts_created AS ts_response
  FROM
    datalake_bigfone_clean.event AS e
  LEFT JOIN
    datalake_customer_support.tickets AS t
      ON t.id_twilio = e.id_task
      OR t.id_twilio = e.id_call
  WHERE
    (
    e.year > YEAR(DATE('{load_start_date}') - INTERVAL 1 YEAR)
    OR (
      e.year = YEAR(DATE('{load_start_date}') - INTERVAL 1 YEAR)
      AND e.month > MONTH(DATE('{load_start_date}') - INTERVAL 1 YEAR)
    ) OR (
      e.year = YEAR(DATE('{load_start_date}') - INTERVAL 1 YEAR)
      AND e.month = MONTH(DATE('{load_start_date}') - INTERVAL 1 YEAR)
      AND e.day >= DAY(DATE('{load_start_date}') - INTERVAL 1 YEAR)
    )
  )
    AND e.csat_2 is not null
  UNION ALL
  SELECT DISTINCT
    c.id_ticket,
    'chatfup' AS source,
    sa.rating AS csat_score,
    NULLIF(sa.comment, '') AS csat_comment,
    TRUE AS is_answered,
    sa.is_solved,
    sa.ts_created AS ts_response
  FROM
    datalake_chat_fup_clean.chats_chat AS c
  INNER JOIN
    datalake_chat_fup_clean.surveys_survey AS ss
      ON ss.id_chat = c.id
  LEFT JOIN
    datalake_chat_fup_clean.surveys_answer AS sa
      ON ss.id = sa.id_survey
  WHERE
    DATE(c.ts_attended) BETWEEN DATE('{load_start_date}') - INTERVAL 1 YEAR AND DATE('{load_end_date}')
    AND sa.id IS NOT NULL
    AND sa.rating IS NOT NULL
)
SELECT DISTINCT
  c.id_ticket,
  ARRAY_AGG(c.source) OVER(PARTITION BY c.id_ticket) AS sources,
  FIRST(c.csat_score) OVER(PARTITION BY c.id_ticket ORDER BY c.ts_response) AS first_csat_score,
  FIRST(c.csat_score) OVER(PARTITION BY c.id_ticket ORDER BY c.ts_response DESC) AS last_csat_score,
  FIRST(c.csat_comment) OVER(PARTITION BY c.id_ticket ORDER BY c.ts_response) AS first_csat_comment,
  FIRST(c.csat_comment) OVER(PARTITION BY c.id_ticket ORDER BY c.ts_response DESC) AS last_csat_comment,
  MAX(c.is_answered) OVER(PARTITION BY c.id_ticket) AS is_answered,
  CASE WHEN
    t.ts_solved IS NULL
    THEN is_solved = FALSE
    ELSE TRUE
  END AS is_solved,
  MIN(c.ts_response) OVER(PARTITION BY c.id_ticket) AS ts_first_response,
  MAX(c.ts_response) OVER(PARTITION BY c.id_ticket) AS ts_last_response
FROM
  csat AS c
LEFT JOIN datalake_customer_support.tickets AS t
  ON t.id_ticket = c.id_ticket
QUALIFY ROW_NUMBER() OVER(PARTITION BY c.id_ticket ORDER BY c.ts_response DESC) = 1
