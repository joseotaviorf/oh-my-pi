WITH greenseer_sessions AS (
  SELECT
    id_session,
    COALESCE(GET_JSON_OBJECT(memory, '$.legacy.user_data.user.id'),get_json_object(memory, '$.basic.user.id')) as id_user,
    id_pipeline,
    GET_JSON_OBJECT(memory, '$.predictions.intents.before_reception.intent') as before_reception,
    GET_JSON_OBJECT(memory, '$.predictions.intents.after_reception.intent') as after_reception,
    GET_JSON_OBJECT(memory, '$.basic.session.context_message') as context_message,
    GET_JSON_OBJECT(memory, '$.basic.session.created_by_hsm') as created_by_hsm,
    GET_JSON_OBJECT(memory, '$.business_rules.tags.added') as tags_added,
    GET_JSON_OBJECT(memory, '$.basic.flags') as flags,
    GET_JSON_OBJECT(memory, '$.basic.user.more_help_required') as more_help_required,
    current_state,
    ts_started,
    ts_ended
  FROM
    datalake_greenseer_clean.session
),
greenseer_retentions as (
  SELECT 
    id_session,
    CASE 
      WHEN session.agent = 'QuintoAndar' or session.agent is null THEN false 
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
    AND ((before_reception <> '' AND before_reception <> 'fallback' AND before_reception IS NOT NULL) OR (after_reception <> '' AND after_reception <> 'fallback' AND after_reception IS NOT NULL))
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