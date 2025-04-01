WITH greenseer_uniques AS (
  SELECT
    id_session,
    id_pipeline,
    memory,
    current_state,
    ts_updated,
    ts_started,
    ts_ended
  FROM
    datalake_greenseer_clean.session
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) = 1
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
    AND journey_name IS NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_correlation ORDER BY ts_created, ts_updated DESC) = 1
),
greenseer_sessions AS (
  SELECT
    g.id_session,
    COALESCE(
      GET_JSON_OBJECT(g.memory, '$.legacy.user_data.user.id'),
      GET_JSON_OBJECT(g.memory, '$.basic.user.id')
    ) AS id_user,
    GET_JSON_OBJECT(g.memory,'$.basic.user.contract.deeplink.contract_id') AS id_contract,
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
      NULLIF(GET_JSON_OBJECT(g.memory,'$.business_rules.menu_taxonomies.selected_taxonomy'),''),
      NULLIF(GET_JSON_OBJECT(g.memory,'$.business_rules.confused_class.selected_theme_detail'),''),
      NULLIF(GET_JSON_OBJECT(g.memory,'$.business_rules.menu_theme_details.selected_theme_detail'),''),
      NULLIF(GET_JSON_OBJECT(g.memory, '$.business_rules.theme_details.predicted_theme_detail'),'')
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
      WHEN CONTAINS((GET_JSON_OBJECT(g.memory, '$.business_rules.tags.added')), 'bot_menu_automatic_selection_intent') THEN 'bot_automatic_selection_intent'
      WHEN CONTAINS((GET_JSON_OBJECT(g.memory, '$.business_rules.tags.added')), 'bot_menu_automatic_selection_taxonomy') THEN 'bot_menu_automatic_selection_taxonomy'
      WHEN CONTAINS((GET_JSON_OBJECT(g.memory, '$.business_rules.tags.added')), 'bot_automatic_selection_theme_detail') THEN 'bot_menu_automatic_selection_taxonomy_v4'
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
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
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
    g.id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy', 'in_app_main','mx_whatsapp_main')
    AND s.source IN ('whatsapp', 'internal_chat','call_in_app')
    AND s.source_environment IN ('default', 'QuintoandarSupport', 'QuintoandarSupport:DEFAULT')
    AND s.status = 'expired'
    AND g.tried_retention
),
sessions_and_tickets AS (
  SELECT DISTINCT
    id_session,
    id_ticket,
    ticket_origin
  FROM
    datalake_customer_support.tickets
  WHERE
    front_or_back = 'front'
    AND ticket_origin IN ('call in app', 'whatsapp', 'chat in app')
),
sessions_with_recontact AS (
  SELECT DISTINCT
    gs.id_session,
    CASE
      WHEN gs.response_key = LAG(gs.response_key, 1) OVER(PARTITION BY gs.id_user ORDER BY ts_started) THEN True
      else False
    END AS has_same_previous_theme,
    CASE
        WHEN ((TO_UNIX_TIMESTAMP(gs.ts_started) - TO_UNIX_TIMESTAMP(LAG(gs.ts_started) OVER (PARTITION BY gs.id_user ORDER BY gs.ts_started)))/(3600)) <= 12 THEN '<12h'
        WHEN ((TO_UNIX_TIMESTAMP(gs.ts_started) - TO_UNIX_TIMESTAMP(LAG(gs.ts_started) OVER (PARTITION BY gs.id_user ORDER BY gs.ts_started)))/(3600)) > 12
          AND ((TO_UNIX_TIMESTAMP(gs.ts_started) - TO_UNIX_TIMESTAMP(LAG(gs.ts_started) OVER (PARTITION BY gs.id_user ORDER BY gs.ts_started)))/(3600)) <= 96 THEN '12-96h'
        WHEN ((TO_UNIX_TIMESTAMP(gs.ts_started) - TO_UNIX_TIMESTAMP(LAG(gs.ts_started) OVER (PARTITION BY gs.id_user ORDER BY gs.ts_started)))/(3600)) > 96 THEN '>96h'
        ELSE 'NR'
    END AS recontact_time
  FROM greenseer_sessions AS gs
    LEFT JOIN datalake_journey_flow_clean.journey_flow j
      ON gs.id_session = j.id_correlation
      AND j.journey_name is null
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY gs.id_session ORDER BY gs.ts_started DESC) = 1
)
SELECT DISTINCT
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
  gs.problem_solved as is_problem_solved,
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
  DAY(gs.ts_started) AS day,
  NOW() AS ts_load
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
