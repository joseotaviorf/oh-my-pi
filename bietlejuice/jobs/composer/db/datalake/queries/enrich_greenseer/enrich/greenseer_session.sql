WITH greenseer_sessions AS (
  SELECT
    id_session,
    COALESCE(GET_JSON_OBJECT(memory, '$.legacy.user_data.user.id'),get_json_object(memory, '$.basic.user.id')) AS id_user,
    id_pipeline,
    GET_JSON_OBJECT(memory, '$.predictions.intents.before_reception.intent') AS before_reception,
    GET_JSON_OBJECT(memory, '$.predictions.intents.after_reception.intent') AS after_reception,
    GET_JSON_OBJECT(memory, '$.basic.session.context_message') AS context_message,
    GET_JSON_OBJECT(memory, '$.basic.session.created_by_hsm') AS created_by_hsm,
    GET_JSON_OBJECT(memory, '$.business_rules.tags.added') AS tags_added,
    GET_JSON_OBJECT(memory, '$.basic.flags') AS flags,
    GET_JSON_OBJECT(memory, '$.basic.user.more_help_required') AS more_help_required,
    GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.response_key') AS response_key,
    CASE 
	      WHEN
	            GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.message') IS NULL
	            OR GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.message') = '' THEN FALSE 
	      ELSE TRUE
    END AS is_menu_available,
    current_state,
    ts_started,
    ts_ended
  FROM
    datalake_greenseer_clean.session
),
greenseer_retentions AS (
  SELECT 
    id_session,
    CASE 
        WHEN 
             session.agent = 'QuintoAndar' 
             OR session.agent is null THEN false 
        ELSE true
    END AS is_retention
  FROM
    greenseer_sessions
  LEFT JOIN
    datalake_sauron_clean.session
      ON session.id = greenseer_sessions.id_session
  WHERE
    id_pipeline IN ('whatsapp', 'whatsapp_main', 'whatsapp_main_legacy')
    AND session.source = 'whatsapp'
    AND session.source_environment = 'default' 
    AND session.status = 'expired'
    AND ((before_reception <> '' AND before_reception <> 'fallback' AND before_reception IS NOT NULL) OR (after_reception <> '' AND after_reception <> 'fallback' AND after_reception IS NOT NULL) OR (response_key IS NOT NULL AND response_key <> ''))
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
  before_reception,
  after_reception,
  is_retention,
  response_key,
  is_menu_available,
  context_message,
  created_by_hsm,
  tags_added,
  flags,
  current_state,
  more_help_required,
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