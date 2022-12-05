WITH greenseer_uniques AS (
  SELECT
    id_session,
    id_pipeline,
    memory,
    current_state,
    ts_started,
    ts_ended
  FROM
    datalake_greenseer_clean.session
  QUALIFY
    RANK() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) = 1
),
journeys_uniques AS (
  SELECT
    id_correlation,
    id_content,
    'journey_flow' AS fired_response
  FROM
    datalake_journey_flow_clean.journey_flow
  WHERE
    fired_response
  QUALIFY
    RANK() OVER (PARTITION BY id_correlation ORDER BY ts_created, ts_updated DESC) = 1
),
greenseer_sessions AS (
  SELECT
    g.id_session,
    COALESCE(
        GET_JSON_OBJECT(g.memory, '$.legacy.user_data.user.id'),
        GET_JSON_OBJECT(g.memory, '$.basic.user.id')
    ) AS id_user,
    g.id_pipeline,
    j.id_content,
    j.fired_response,
    NULLIF(
      GET_JSON_OBJECT(g.memory,'$.predictions.intents.before_reception.intent'), ''
    ) AS before_reception,
    NULLIF(
      GET_JSON_OBJECT(g.memory,'$.predictions.intents.after_reception.intent'), ''
    ) AS after_reception,
    GET_JSON_OBJECT(g.memory, '$.basic.session.context_message') AS context_message,
    GET_JSON_OBJECT(g.memory, '$.basic.session.created_by_hsm') AS created_by_hsm,
    GET_JSON_OBJECT(g.memory, '$.business_rules.tags.added') AS tags_added,
    GET_JSON_OBJECT(g.memory, '$.basic.flags') AS flags,
    GET_JSON_OBJECT(g.memory, '$.basic.user.more_help_required') AS more_help_required,
    NULLIF(
      GET_JSON_OBJECT(g.memory,'$.business_rules.menu_taxonomies.response_key'), ''
    ) AS response_key,
    (
      COALESCE(
        GET_JSON_OBJECT(g.memory, '$.business_rules.menu_taxonomies.message'), ''
      ) <> ''
    ) AS is_menu_available,
    (
      COALESCE(
        GET_JSON_OBJECT(g.memory, '$.experiments.experiment_merge_dialogflow_and_menu'), ''
      ) = 'merged_retention_attempt_block'
    ) AS menu_new_style,
    g.current_state,
    g.ts_started,
    g.ts_ended
  FROM
    greenseer_uniques AS g
  LEFT JOIN
    journeys_uniques AS j
      ON j.id_correlation = g.id_session
),
greenseer_tried_retention AS (
  SELECT
    id_session,
    id_pipeline,
    CASE
      WHEN menu_new_style OR DATE_TRUNC('DD', ts_started) > '2022-06-27' THEN (
        COALESCE(NULLIF(before_reception, 'fallback'), response_key, fired_response) IS NOT NULL
      )
      ELSE (
        COALESCE(
          NULLIF(before_reception, 'fallback'),
          NULLIF(after_reception, 'fallback'),
          response_key,
          fired_response
        ) IS NOT NULL
      )
    END AS tried_retention
  FROM
    greenseer_sessions
),
sauron_uniques AS (
  SELECT
    id,
    source,
    source_environment,
    agent,
    status,
    ts_last_message,
    ts_first_message
  FROM
    datalake_sauron_clean.session
  QUALIFY
    RANK() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
),
greenseer_retentions AS (
  SELECT
    g.id_session,
    (s.agent IS NOT NULL AND s.agent <> 'QuintoAndar') AS is_retention
  FROM
    greenseer_tried_retention AS g
  LEFT JOIN
    sauron_uniques AS s
      ON s.id = g.id_session
  WHERE
    g.id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy')
    AND s.source = 'whatsapp'
    AND s.source_environment = 'default'
    AND s.status = 'expired'
    AND g.tried_retention
),
sessions_and_tickets AS (
  SELECT DISTINCT
    id_session,
    id_ticket
  FROM
    datalake_customer_support.chat
  WHERE
    front_or_back = 'front'
)
SELECT
  greenseer_sessions.id_session,
  id_ticket,
  greenseer_sessions.id_user,
  id_pipeline,
  id_content,
  (fired_response IS NOT NULL) AS has_journey_flow_response,
  before_reception,
  after_reception,
  response_key,
  context_message,
  created_by_hsm,
  tags_added,
  flags,
  current_state,
  is_menu_available,
  more_help_required AS is_more_help_required,
  is_retention,
  CASE
    WHEN greenseer_sessions.ts_ended > greenseer_sessions.ts_started + INTERVAL '72 hour' THEN TRUE
    ELSE FALSE
  END AS has_exceeded_session_timeout,
  greenseer_sessions.ts_started,
  greenseer_sessions.ts_ended
FROM
  greenseer_sessions
LEFT JOIN
  greenseer_retentions
    USING(id_session)
LEFT JOIN
  sessions_and_tickets
    USING(id_session)
