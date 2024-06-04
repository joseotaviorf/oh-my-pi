WITH surveys_fup AS (
  SELECT
    GET_JSON_OBJECT(custom_attributes, '$.id_origin') AS id_session,
    id_survey,
    id_answer
  FROM
    datalake_satisfaction_rating.chat_fup_surveys
  WHERE
    GET_JSON_OBJECT(custom_attributes, '$.id_origin') IS NOT NULL
),
base_churn AS (
  SELECT DISTINCT
    gs.id_user,
    gs.ts_started,
    CASE
      WHEN (
        gs.id_user IS NOT NULL
        AND gs.ts_started IS NOT NULL
      ) OR gs.id_user IS NULL THEN 'chat'
      WHEN call.id_user IS NOT NULL  AND call.ts_ticket_started IS NOT NULL THEN 'call'
      ELSE 'chat'
    END AS channel
  FROM
    datalake_greenseer.sessions AS gs
  LEFT JOIN
    datalake_customer_support.call AS call
      ON gs.id_user = CAST(call.id_user AS STRING)
      AND gs.ts_started < call.ts_ticket_started
  WHERE
    gs.is_retention IS TRUE
    AND YEAR(gs.ts_started) >= 2024
),
churn_to_call AS (
  SELECT
    id_user,
    channel,
    ts_started,
    LAG(channel, 1) OVER(PARTITION BY id_user ORDER BY ts_started) AS previews_channel,
    LAG(ts_started, 1) OVER(PARTITION BY id_user ORDER BY ts_started) AS previews_contact_date,
    CASE
      WHEN channel = 'chat'
        AND LAG(channel, 1) OVER(PARTITION BY id_user ORDER BY ts_started) = 'chat'
        AND (unix_timestamp(ts_started) - unix_timestamp(LAG(ts_started, 1) OVER(PARTITION BY id_user ORDER BY ts_started))) / 3600  <= 96 THEN 0
      WHEN channel = 'call'
        AND LAG(channel, 1) OVER(PARTITION BY id_user ORDER BY ts_started) = 'chat'
        AND (unix_timestamp(ts_started) - unix_timestamp(LAG(ts_started, 1) OVER(PARTITION BY id_user ORDER BY ts_started))) / 3600  <= 96 THEN 1 -- considerando que o cliente churnou se abriu uma sessão por call em até 96h após ser retido no chat
    END AS is_churn_chat
  FROM
    base_churn
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
    WHEN gs.is_retention <> true AND gs.id_ticket IS NULL THEN 1
    ELSE 0
  END AS is_abandonmet,
  gs.is_recontact,
  CASE
    WHEN gs.is_retention = true AND gs.has_fallback = true THEN 1
    ELSE 0
  END AS is_retained_session_with_fallback,
  cc.is_churn_chat,
  IF(gs.ticket_origin = 'call inapp', 1, 0) AS is_call_in_app_session,
  gs.has_exceeded_session_timeout,
  gs.has_journey_flow_response,
  gs.has_fallback,
  CASE
    WHEN GET_JSON_OBJECT(gs.memory, '$.basic.session.number_interactions') IS NULL THEN 1
    ELSE GET_JSON_OBJECT(gs.memory, '$.basic.session.number_interactions')
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
    WHEN gs.current_state LIKE '%CSAT%' THEN 1 ELSE 0
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
  churn_to_call AS cc
    ON  gs.id_user = cc.id_user
    AND cc.previews_contact_date = gs.ts_started
WHERE
    gs.year = {year}
    AND gs.month = {month}
    AND gs.day = {day}
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY gs.id_session ORDER BY gs.ts_updated DESC) = 1
