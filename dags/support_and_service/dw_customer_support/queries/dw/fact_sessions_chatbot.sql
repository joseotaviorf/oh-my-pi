WITH greenseer_uniques_ranked AS (
  SELECT
    id_session,
    id_pipeline,
    memory,
    current_state,
    ts_updated,
    ts_started,
    ts_ended,
    ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) AS rn
  FROM
    datalake_greenseer_clean.session
  WHERE
    ts_started >= DATE('{load_start_date}') - INTERVAL 3 MONTH
),
greenseer_uniques AS (
  SELECT
    id_session,
    id_pipeline,
    memory,
    current_state,
    ts_updated,
    ts_started,
    ts_ended
  FROM
    greenseer_uniques_ranked
  WHERE
    rn = 1
),
journeys_ranked AS (
  SELECT
    id_correlation,
    id_content,
    'journey_flow' AS fired_response,
    ROW_NUMBER() OVER (PARTITION BY id_correlation ORDER BY ts_created, ts_updated DESC) AS rn
  FROM
    datalake_journey_flow_clean.journey_flow
  WHERE
    fired_response
    AND journey_name IS NULL
),
journeys_uniques AS (
  SELECT
    id_correlation,
    id_content,
    fired_response
  FROM
    journeys_ranked
  WHERE
    rn = 1
),
greenseer_sessions AS (
  SELECT
    g.id_session,
    COALESCE(
      GET_JSON_OBJECT(g.memory, '$.legacy.user_data.user.id'),
      GET_JSON_OBJECT(g.memory, '$.basic.user.id')
    ) AS id_user,
    GET_JSON_OBJECT(g.memory, '$.basic.user.contract.deeplink.contract_id') AS id_contract,
    g.id_pipeline,
    j.id_content,
    j.fired_response,
    NULLIF(
      GET_JSON_OBJECT(g.memory, '$.predictions.intents.before_reception.intent'), ''
    ) AS before_reception,
    NULLIF(
      GET_JSON_OBJECT(g.memory, '$.predictions.intents.after_reception.intent'), ''
    ) AS after_reception,
    GET_JSON_OBJECT(g.memory, '$.basic.session.context_message') AS context_message,
    GET_JSON_OBJECT(g.memory, '$.basic.session.created_by_hsm') AS created_by_hsm,
    GET_JSON_OBJECT(g.memory, '$.business_rules.tags.added') AS tags,
    GET_JSON_OBJECT(g.memory, '$.basic.flags') AS flags,
    CAST(
      COALESCE(
        GET_JSON_OBJECT(g.memory, '$.business_rules.more_help_required.no_answer_needed.value'),
        GET_JSON_OBJECT(g.memory, '$.business_rules.more_help_required.before_reception.value'),
        GET_JSON_OBJECT(g.memory, '$.business_rules.more_help_required.confirm_bypass_hsm.value')
      ) AS BOOLEAN
    ) AS more_help_required,
    CAST(
      COALESCE(
        GET_JSON_OBJECT(g.memory, '$.business_rules.problem_solved_required.after_reception.value'),
        GET_JSON_OBJECT(g.memory, '$.business_rules.problem_solved_required.direct_answer.value')
      ) AS BOOLEAN
    ) AS problem_solved,
    COALESCE(
      NULLIF(GET_JSON_OBJECT(g.memory, '$.business_rules.menu_taxonomies.selected_taxonomy'), ''),
      NULLIF(GET_JSON_OBJECT(g.memory, '$.business_rules.confused_class.selected_theme_detail'), ''),
      NULLIF(GET_JSON_OBJECT(g.memory, '$.business_rules.menu_theme_details.selected_theme_detail'), ''),
      NULLIF(GET_JSON_OBJECT(g.memory, '$.business_rules.theme_details.predicted_theme_detail'), '')
    ) AS response_key,
    (
      COALESCE(
        GET_JSON_OBJECT(g.memory, '$.business_rules.menu_taxonomies.message'),
        GET_JSON_OBJECT(g.memory, '$.business_rules.confused_class.message'),
        GET_JSON_OBJECT(g.memory, '$.business_rules.menu_theme_details.message'),
        ''
      ) <> ''
    ) AS is_menu_available,
    CASE
      WHEN CONTAINS(GET_JSON_OBJECT(g.memory, '$.business_rules.tags.added'), 'bot_menu_automatic_selection_intent') THEN 'bot_automatic_selection_intent'
      WHEN CONTAINS(GET_JSON_OBJECT(g.memory, '$.business_rules.tags.added'), 'bot_menu_automatic_selection_taxonomy') THEN 'bot_menu_automatic_selection_taxonomy'
      WHEN CONTAINS(GET_JSON_OBJECT(g.memory, '$.business_rules.tags.added'), 'bot_automatic_selection_theme_detail') THEN 'bot_menu_automatic_selection_taxonomy_v4'
      ELSE NULL
    END AS automatic_selection,
    GET_JSON_OBJECT(g.memory, '$.business_rules.journey_flow.retention_emma.emma_try') AS has_emma_try,
    GET_JSON_OBJECT(g.memory, '$.business_rules.journey_flow.retention_emma.has_retention_response') AS has_emma_response,
    CASE
      WHEN CONTAINS(g.current_state, 'RETENTION_EMMA') THEN 'has_emma_flow'
      ELSE NULL
    END AS has_emma_flow,
    GET_JSON_OBJECT(g.memory, '$.business_rules.journey_flow.retention_emma.fallback') AS has_fallback,
    g.memory,
    g.current_state,
    g.ts_updated,
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
    COALESCE(
      NULLIF(before_reception, 'fallback'),
      NULLIF(after_reception, 'fallback'),
      response_key,
      automatic_selection,
      fired_response,
      has_emma_response,
      has_emma_try,
      has_emma_flow
    ) IS NOT NULL AS tried_retention
  FROM
    greenseer_sessions
),
sauron_ranked AS (
  SELECT
    id,
    source,
    source_environment,
    agent,
    status,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS rn
  FROM
    datalake_sauron_clean.session
),
sauron_uniques AS (
  SELECT
    id,
    source,
    source_environment,
    agent,
    status
  FROM
    sauron_ranked
  WHERE
    rn = 1
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
    g.id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy', 'in_app_main', 'mx_whatsapp_main')
    AND s.source IN ('whatsapp', 'internal_chat', 'call_in_app')
    AND s.source_environment IN ('default', 'QuintoandarSupport', 'QuintoandarSupport:DEFAULT')
    AND s.status = 'expired'
    AND g.tried_retention
),
sessions_and_tickets_ranked AS (
  SELECT
    id_session,
    id_ticket,
    ticket_origin,
    ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) AS rn
  FROM
    datalake_customer_support.tickets
  WHERE
    front_or_back = 'front'
    AND ticket_origin IN ('call in app', 'whatsapp', 'chat in app')
),
sessions_and_tickets AS (
  SELECT
    id_session,
    id_ticket,
    ticket_origin
  FROM
    sessions_and_tickets_ranked
  WHERE
    rn = 1
),
sessions_with_recontact_ranked AS (
  SELECT
    gs.id_session,
    CASE
      WHEN gs.response_key = LAG(gs.response_key, 1) OVER (PARTITION BY gs.id_user ORDER BY ts_started) THEN True
      ELSE False
    END AS has_same_previous_theme,
    CASE
      WHEN ((TO_UNIX_TIMESTAMP(gs.ts_started) - TO_UNIX_TIMESTAMP(LAG(gs.ts_started) OVER (PARTITION BY gs.id_user ORDER BY gs.ts_started))) / (3600)) <= 12 THEN '<12h'
      WHEN ((TO_UNIX_TIMESTAMP(gs.ts_started) - TO_UNIX_TIMESTAMP(LAG(gs.ts_started) OVER (PARTITION BY gs.id_user ORDER BY gs.ts_started))) / (3600)) > 12
        AND ((TO_UNIX_TIMESTAMP(gs.ts_started) - TO_UNIX_TIMESTAMP(LAG(gs.ts_started) OVER (PARTITION BY gs.id_user ORDER BY gs.ts_started))) / (3600)) <= 96 THEN '12-96h'
      WHEN ((TO_UNIX_TIMESTAMP(gs.ts_started) - TO_UNIX_TIMESTAMP(LAG(gs.ts_started) OVER (PARTITION BY gs.id_user ORDER BY gs.ts_started))) / (3600)) > 96 THEN '>96h'
      ELSE 'NR'
    END AS recontact_time,
    ROW_NUMBER() OVER (PARTITION BY gs.id_session ORDER BY gs.ts_started DESC) AS rn
  FROM
    greenseer_sessions AS gs
  LEFT JOIN
    datalake_journey_flow_clean.journey_flow AS j
      ON gs.id_session = j.id_correlation
      AND j.journey_name IS NULL
),
sessions_with_recontact AS (
  SELECT
    id_session,
    has_same_previous_theme,
    recontact_time
  FROM
    sessions_with_recontact_ranked
  WHERE
    rn = 1
),
greenseer_enriched AS (
  SELECT
    gs.id_session,
    st.id_ticket,
    gs.id_user,
    gs.id_pipeline,
    gs.id_content,
    gs.id_contract,
    gs.before_reception,
    gs.after_reception,
    gs.response_key,
    gs.automatic_selection,
    gs.context_message,
    gs.created_by_hsm,
    gs.tags,
    gs.flags,
    gs.current_state,
    sr.recontact_time,
    gs.memory,
    (gs.fired_response IS NOT NULL) AS has_journey_flow_response,
    gs.is_menu_available,
    gs.more_help_required AS is_more_help_required,
    gs.problem_solved AS is_problem_solved,
    gr.is_retention,
    IF(
      sr.has_same_previous_theme = True
      AND sr.recontact_time IN ('12-96h')
      AND gr.is_retention = True, True, False
    ) AS is_recontact,
    sr.has_same_previous_theme,
    CASE
      WHEN gs.ts_ended > gs.ts_started + INTERVAL '4 hour' THEN True
      ELSE False
    END AS has_exceeded_session_timeout,
    gs.has_fallback,
    st.ticket_origin,
    gs.ts_started,
    gs.ts_ended,
    gs.ts_updated,
    YEAR(gs.ts_started) AS year,
    MONTH(gs.ts_started) AS month,
    DAY(gs.ts_started) AS day
  FROM
    greenseer_sessions AS gs
  LEFT JOIN
    greenseer_retentions AS gr
      ON gr.id_session = gs.id_session
  LEFT JOIN
    sessions_and_tickets AS st
      ON st.id_session = gs.id_session
  LEFT JOIN
    sessions_with_recontact AS sr
      ON sr.id_session = gs.id_session
),
surveys_fup AS (
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
    g.id_user,
    g.ts_started,
    'chat' AS channel
  FROM
    greenseer_enriched AS g
  WHERE
    g.ts_started >= DATE('{load_start_date}') - INTERVAL 3 MONTH
    AND is_retention = TRUE
  UNION
  SELECT
    CAST(t.id_user_main AS STRING) AS id_user,
    t.ts_created - INTERVAL 3 HOUR AS ts_started,
    'call' AS channel
  FROM
    datalake_customer_support.tickets AS t
  JOIN
    greenseer_enriched AS g
      ON
        CAST(t.id_user_main AS STRING) = g.id_user
        AND g.ts_started < t.ts_created - INTERVAL 3 HOUR
  WHERE
    t.channel = 'call'
    AND g.ts_started >= DATE('{load_start_date}') - INTERVAL 3 MONTH
),
assistances AS (
  SELECT
    id_user,
    channel,
    ts_started,
    LAG(channel) OVER (PARTITION BY id_user ORDER BY ts_started) AS previews_channel,
    LAG(ts_started) OVER (PARTITION BY id_user ORDER BY ts_started) AS previews_contact_date,
    (TO_UNIX_TIMESTAMP(ts_started) - TO_UNIX_TIMESTAMP(
      LAG(ts_started, 1) OVER (PARTITION BY id_user ORDER BY ts_started ASC)
    )) / (3600) hours_to_next_session
  FROM
    base_churn
),
wrangling AS (
  SELECT
    id_user,
    ts_started,
    previews_contact_date,
    CASE
      WHEN channel = 'call' AND previews_channel = 'chat' AND hours_to_next_session <= 96 THEN True
      WHEN channel = 'chat' AND previews_channel = 'chat' AND hours_to_next_session <= 96 THEN False
    END AS is_churn_chat
  FROM
    assistances
  WHERE
    previews_channel = 'chat'
),
options_response AS (
  SELECT
    id_session,
    ts_started,
    SIZE(COALESCE(
      MAP_KEYS(FROM_JSON(GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.options'), 'map<string, struct<name:string,class:string,score:double>>')),
      MAP_KEYS(FROM_JSON(GET_JSON_OBJECT(memory, '$.business_rules.menu_confused_class.options'), 'map<string, struct<name:string,class:string,score:double>>')),
      MAP_KEYS(FROM_JSON(GET_JSON_OBJECT(memory, '$.business_rules.menu_theme_details.options'), 'map<string, struct<name:string,class:string,score:double>>'))
    )) AS n_options,
    REGEXP_REPLACE(REGEXP_EXTRACT(
      element_at(
        ARRAY(
          COALESCE(
            GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.raw_answers'),
            GET_JSON_OBJECT(memory, '$.business_rules.menu_confused_class.raw_answers'),
            GET_JSON_OBJECT(memory, '$.business_rules.menu_theme_details.raw_answers')
          )), -1
        ),
    '\\d+', 0), '^0+', '') AS raw_answer_last
  FROM
    greenseer_enriched
  WHERE
    ts_started BETWEEN DATE('{load_start_date}') - INTERVAL 3 MONTH AND DATE('{load_end_date}')
    AND response_key IS NOT NULL
),
normalize_options AS (
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
  FROM
    options_response
),
deduped AS (
  SELECT
    gs.id_session AS sk_session,
    COALESCE(gs.id_ticket, -1) AS sk_ticket,
    COALESCE(CAST(gs.id_user AS BIGINT), -1) AS sk_user,
    COALESCE(gs.id_pipeline, -1) AS sk_pipeline,
    COALESCE(gs.id_content, -1) AS sk_content,
    COALESCE(CAST(gs.id_contract AS BIGINT), -1) AS sk_contract,
    COALESCE(sf.id_survey, -1) AS sk_survey,
    COALESCE(sf.id_answer, -1) AS sk_answer,
    COALESCE(CAST(DATE_FORMAT(gs.ts_started, 'yyyyMMdd') AS BIGINT), -1) AS sk_started_chat,
    COALESCE(CAST(DATE_FORMAT(gs.ts_ended, 'yyyyMMdd') AS BIGINT), -1) AS sk_ended_chat,
    gs.recontact_time,
    gs.is_menu_available,
    gs.is_more_help_required,
    gs.is_problem_solved,
    gs.is_retention,
    CASE
      WHEN gs.is_retention <> true AND gs.id_ticket IS NULL THEN True
      ELSE FALSE
    END AS is_abandonmet,
    gs.is_recontact,
    CASE
      WHEN gs.is_retention = true AND gs.has_fallback = true THEN True
      ELSE FALSE
    END AS is_retained_session_with_fallback,
    IFNULL(w.is_churn_chat, FALSE) AS is_churn_chat,
    nop.user_response IS NOT NULL AND nop.n_options IS NOT NULL AND nop.user_response = n_options + 1 AS is_other_option,
    IF(gs.ticket_origin = 'call in app', True, False) AS is_call_in_app_session,
    gs.has_exceeded_session_timeout,
    gs.has_journey_flow_response,
    gs.has_fallback,
    CASE
      WHEN GET_JSON_OBJECT(gs.memory, '$.basic.session.number_interactions') IS NULL THEN 0
      ELSE CAST(GET_JSON_OBJECT(gs.memory, '$.basic.session.number_interactions') AS DECIMAL)
    END AS number_chat_interactions,
    GET_JSON_OBJECT(gs.memory, '$.predictions.with_context') AS model_with_context,
    GET_JSON_OBJECT(gs.memory, '$.predictions.no_context') AS model_no_context,
    GET_JSON_OBJECT(gs.memory, '$.predictions.greeting') AS model_greeting,
    GET_JSON_OBJECT(gs.memory, '$.predictions.no_answer_needed') AS model_no_answer_needed,
    gs.before_reception,
    gs.after_reception,
    GET_JSON_OBJECT(gs.memory, '$.basic.session.last_hsm.type') AS last_hsm_type,
    CAST(GET_JSON_OBJECT(gs.memory, '$.basic.session.last_hsm.secs_since') AS FLOAT) AS secs_since_last_hsm,
    gs.automatic_selection,
    CASE
      WHEN gs.current_state LIKE '%CSAT%' THEN True ELSE False
    END AS has_questionnaire_sent,
    CASE
      WHEN
        CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_hsm') <> True
        AND CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_partners') <> True
        OR CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_hsm') IS NULL
        AND CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_partners') <> True
        OR CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_hsm') <> True
        AND CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_partners') IS NULL
        OR CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_hsm') IS NULL
        AND CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_partners') IS NULL
      THEN False
      WHEN
        CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_hsm') = True
        OR CONTAINS(GET_JSON_OBJECT(gs.memory, '$.business_rules.tags.added'), 'bot_bypass_triage_partners') = True
      THEN True
      ELSE NULL
    END AS has_valid_hsm_bypass,
    SIZE(
      FROM_JSON(
        GET_JSON_OBJECT(gs.memory, '$.business_rules.context_detection_attempts'),
        'array<map<string, map<string, double>>>'
      )) AS context_identification_tentatives,
    gs.has_same_previous_theme,
    gs.year,
    gs.month,
    gs.day,
    ROW_NUMBER() OVER (PARTITION BY gs.id_session ORDER BY gs.ts_updated DESC) AS rn
  FROM
    greenseer_enriched AS gs
  LEFT JOIN
    surveys_fup AS sf
      ON gs.id_session = sf.id_session
  LEFT JOIN
    wrangling AS w
      ON gs.id_user = w.id_user
      AND w.previews_contact_date = gs.ts_started
  LEFT JOIN
    normalize_options AS nop
      ON gs.id_session = nop.id_session
  WHERE
    gs.ts_started >= DATE('{load_start_date}') - INTERVAL 3 MONTH
)
SELECT
  sk_session,
  sk_ticket,
  sk_user,
  sk_pipeline,
  sk_content,
  sk_contract,
  sk_survey,
  sk_answer,
  sk_started_chat,
  sk_ended_chat,
  recontact_time,
  is_menu_available,
  is_more_help_required,
  is_problem_solved,
  is_retention,
  is_abandonmet,
  is_recontact,
  is_retained_session_with_fallback,
  is_churn_chat,
  is_other_option,
  is_call_in_app_session,
  has_exceeded_session_timeout,
  has_journey_flow_response,
  has_fallback,
  number_chat_interactions,
  model_with_context,
  model_no_context,
  model_greeting,
  model_no_answer_needed,
  before_reception,
  after_reception,
  last_hsm_type,
  secs_since_last_hsm,
  automatic_selection,
  has_questionnaire_sent,
  has_valid_hsm_bypass,
  context_identification_tentatives,
  has_same_previous_theme,
  year,
  month,
  day,
  NOW() AS ts_load
FROM
  deduped
WHERE
  rn = 1
