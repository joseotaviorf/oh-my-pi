WITH surveys_fup AS (
  SELECT
    GET_JSON_OBJECT(custom_attributes, '$.id_origin') AS id_session,
    id_survey,
    id_answer
  FROM
    datalake_satisfaction_rating.chat_fup_surveys
  WHERE
    GET_JSON_OBJECT(custom_attributes, '$.id_origin') IS NOT NULL
)
,base_churn AS (
  SELECT DISTINCT
    g.id_user,
    g.ts_started,
    'chat' AS channel
  FROM
    datalake_greenseer.sessions g
  WHERE
    MAKE_DATE(g.year, g.month, g.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND is_retention = TRUE

  UNION

  SELECT
    CAST(call.id_user AS STRING) AS id_user,
    call.ts_ticket_started AS ts_started,
    'call' AS channel
  FROM
    datalake_customer_support.call AS call
  JOIN
    datalake_greenseer.sessions AS g
  ON
    CAST(call.id_user AS STRING) = g.id_user
    AND g.ts_started < call.ts_ticket_started
  WHERE
    MAKE_DATE(g.year, g.month, g.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
,assistances AS (
  SELECT
    id_user,
    channel,
    ts_started,
    COALESCE(LAG(channel) OVER (PARTITION BY id_user ORDER BY ts_started), channel) AS previews_channel,
    COALESCE(LAG(ts_started) OVER (PARTITION BY id_user ORDER BY ts_started),ts_started) AS previews_contact_date,
    (TO_UNIX_TIMESTAMP(ts_started) - TO_UNIX_TIMESTAMP(COALESCE(LAG(ts_started) OVER (PARTITION BY id_user ORDER BY ts_started),ts_started))) / 3600 AS hours_to_next_session
  FROM
    base_churn
)
,wrangling AS (
  SELECT
    id_user,
    ts_started,
    previews_contact_date,
    CASE
      WHEN channel = 'call' AND previews_channel = 'chat' AND hours_to_next_session <= 96 THEN True
      ELSE False
    END AS is_churn_chat
  FROM
    assistances
  WHERE
    previews_channel = 'chat'
)
,options_response AS (
  SELECT
    id_session,
    ts_started,
    SIZE(COALESCE(
      map_keys(from_json(get_json_object(memory, '$.business_rules.menu_taxonomies.options'),'map<string, struct<name:string,class:string,score:double>>')),
      map_keys(from_json(get_json_object(memory, '$.business_rules.menu_confused_class.options'),'map<string, struct<name:string,class:string,score:double>>')),
      map_keys(from_json(get_json_object(memory, '$.business_rules.menu_theme_details.options'),'map<string, struct<name:string,class:string,score:double>>'))
    )) AS n_options,
    regexp_replace(regexp_extract(
      element_at(
        ARRAY(
          COALESCE(
            GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.raw_answers'),
            GET_JSON_OBJECT(memory, '$.business_rules.menu_confused_class.raw_answers'),
            GET_JSON_OBJECT(memory, '$.business_rules.menu_theme_details.raw_answers')
          )),-1
        ),
    '\\d+', 0), '^0+', '')  AS raw_answer_last
  FROM datalake_greenseer.sessions
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND response_key IS NOT NULL
)
,normalize_options AS (
  SELECT
    id_session,
    ts_started,
    IF(n_options = -1, NULL, n_options) AS n_options,
    raw_answer_last,
    CASE
      WHEN raw_answer_last IS NULL THEN NULL
      WHEN length(raw_answer_last) = 1 THEN CAST(raw_answer_last AS INT)
      ELSE 10
    END AS user_response
  FROM options_response
)
SELECT
  gs.id_session AS sk_session,
  COALESCE(gs.id_ticket, -1) AS sk_ticket,
  COALESCE(gs.id_user, -1) AS sk_user,
  COALESCE(gs.id_pipeline, -1) AS sk_pipeline,
  COALESCE(gs.id_content, -1) AS sk_content,
  COALESCE(gs.id_contract, -1) AS sk_contract,
  COALESCE(sf.id_survey, -1) AS sk_survey,
  COALESCE(sf.id_answer, -1) AS sk_answer,
  COALESCE(CAST(DATE_FORMAT(gs.ts_started,'yyyyMMdd') AS BIGINT), -1) AS sk_started_chat,
  COALESCE(CAST(DATE_FORMAT(gs.ts_ended,'yyyyMMdd') AS BIGINT), -1) AS sk_ended_chat,
  gs.is_menu_available,
  gs.is_more_help_required,
  gs.is_problem_solved,
  gs.is_retention,
  CASE
    WHEN gs.is_retention <> true AND gs.id_ticket IS NULL THEN True
    ELSE False
  END AS is_abandonmet,
  gs.is_recontact,
  CASE
    WHEN gs.is_retention = true AND gs.has_fallback = true THEN True
    ELSE False
  END AS is_retained_session_with_fallback,
  w.is_churn_chat,
  nop.user_response IS NOT NULL AND nop.n_options IS NOT NULL AND nop.user_response = n_options + 1 AS is_other_option,
  IF(gs.ticket_origin = 'call inapp', True, False) AS is_call_in_app_session,
  gs.has_exceeded_session_timeout,
  gs.has_journey_flow_response,
  gs.has_fallback,
  CASE
    WHEN GET_JSON_OBJECT(gs.memory, '$.basic.session.number_interactions') IS NULL THEN 0
    ELSE CAST(GET_JSON_OBJECT(gs.memory, '$.basic.session.number_interactions') AS DECIMAL)
  END AS number_chat_interactions,
  GET_JSON_OBJECT(gs.memory,'$.predictions.with_context') AS model_with_context,
  GET_JSON_OBJECT(gs.memory,'$.predictions.no_context') AS model_no_context,
  GET_JSON_OBJECT(gs.memory,'$.predictions.greeting') AS model_greeting,
  GET_JSON_OBJECT(gs.memory,'$.predictions.no_answer_needed') AS model_no_answer_needed,
  gs.before_reception,
  gs.after_reception,
  GET_JSON_OBJECT(gs.memory, '$.basic.session.last_hsm.type') AS last_hsm_type,
  GET_JSON_OBJECT(memory, '$.basic.session.last_hsm.secs_since') AS secs_since_last_hsm,
  gs.automatic_selection,
  CASE
    WHEN gs.current_state LIKE '%CSAT%' THEN True ELSE False
  END AS has_questionnaire_sent,
  gs.context_detection_attempts AS context_identification_tentatives,
  gs.has_same_previous_theme,
  gs.year,
  gs.month,
  gs.day,
  NOW() AS ts_load
FROM
  datalake_greenseer.sessions AS gs
LEFT JOIN
  surveys_fup AS sf
    ON gs.id_session = sf.id_session
LEFT JOIN
  wrangling AS w
    ON  gs.id_user = w.id_user
    AND w.previews_contact_date = gs.ts_started
LEFT JOIN
  normalize_options AS nop
    ON gs.id_session = nop.id_session
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY gs.id_session ORDER BY gs.ts_updated DESC) = 1
