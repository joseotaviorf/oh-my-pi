WITH last_session_update AS (
  SELECT
    id_session,
    id_pipeline,
    memory,
    ts_started,
    ts_ended
  FROM
    datalake_greenseer_clean.session
  WHERE
    ts_started >= "2023-01-01"
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) = 1
)
SELECT
  id_session,
  id_pipeline,
  memory,
  GET_JSON_OBJECT(memory, '$.basic.user.id') AS id_user,
  GET_JSON_OBJECT(memory, '$.legacy.user_data.user.id') AS id_user_legacy,
  GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.whatsapp_strategy') AS strategy,
  GET_JSON_OBJECT(memory, '$.predictions.jon_snow.with_context') AS jon_snow_with_context,
  GET_JSON_OBJECT(memory, '$.predictions.jon_snow.no_context') AS jon_snow_no_context,
  GET_JSON_OBJECT(memory, '$.predictions.jon_snow.greeting') AS jon_snow_greeting,
  GET_JSON_OBJECT(memory, '$.predictions.jon_snow.no_answer_needed') AS jon_snow_no_answer_needed,
  GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.selected_taxonomy') AS taxonomy,
  GET_JSON_OBJECT(memory, '$.business_rules.more_help_required.after_reception.value') AS need_more_help_after_reception,
  GET_JSON_OBJECT(memory, '$.business_rules.tags.added') AS tags,
  GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.has_access') AS has_chat_inapp_access,
  GET_JSON_OBJECT(memory, '$.predictions.intents.before_reception.intent') AS before_reception,
  GET_JSON_OBJECT(memory, '$.predictions.intents.after_reception.intent') AS after_reception,
  GET_JSON_OBJECT(memory, '$.basic.session.last_hsm.type') AS last_hsm_type,
  GET_JSON_OBJECT(memory, '$.basic.session.last_hsm.secs_since') AS secs_since_last_hsm,
  ts_started,
  ts_ended
FROM
  last_session_update
