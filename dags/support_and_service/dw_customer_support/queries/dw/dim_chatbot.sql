SELECT
  id_session AS sk_session,
  GET_JSON_OBJECT(memory, '$.basic.user.app_version') AS app_version,
  GET_JSON_OBJECT(memory, '$.business_rules.tags.added') AS tags,
  GET_JSON_OBJECT(memory, '$.business_rules.internal_chat.whatsapp_strategy') AS strategy,
  COALESCE(
    NULLIF(GET_JSON_OBJECT(memory,'$.business_rules.menu_taxonomies.selected_taxonomy'),''),
    NULLIF(GET_JSON_OBJECT(memory,'$.business_rules.confused_class.selected_theme_detail'),''),
    NULLIF(GET_JSON_OBJECT(memory,'$.business_rules.menu_theme_details.selected_theme_detail'),'')
  ) AS selected_taxonomy,
  GET_JSON_OBJECT(memory, '$.basic.session.context_message') AS context_message,
  GET_JSON_OBJECT(memory, '$.basic.flags') AS flags,
  current_state,
  CASE
    WHEN
      GET_JSON_OBJECT(memory, '$.predictions.tags_v4.theme') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v4.theme') <> 'null'
      OR GET_JSON_OBJECT(memory, '$.predictions.tags_v4.theme_detail') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v4.theme_detail') <> 'null'
      OR GET_JSON_OBJECT(memory, '$.predictions.tags_v4.customer_type') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v4.customer_type') <> 'null'
      OR GET_JSON_OBJECT(memory, '$.predictions.jon_snow') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.jon_snow') <> 'null'
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v3') IS NULL
      OR GET_JSON_OBJECT(memory, '$.predictions.jon_snow') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.jon_snow') <> 'null'
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v3') = 'null'
    THEN 'V4'
    WHEN
      GET_JSON_OBJECT(memory, '$.predictions.tags_v3') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v3') <> 'null'
      AND id_pipeline <> 'smarthelp_main'
      AND GET_JSON_OBJECT(memory, '$.predictions.intents.before_reception.intent') IS NULL
      OR GET_JSON_OBJECT(memory, '$.predictions.tags_v3') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v3') <> 'null'
      AND id_pipeline <> 'smarthelp_main'
      AND GET_JSON_OBJECT(memory, '$.predictions.intents.before_reception.intent') = 'null'
      OR GET_JSON_OBJECT(memory, '$.predictions.tags_v3') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v3') <> 'null'
      AND id_pipeline <> 'smarthelp_main'
      AND GET_JSON_OBJECT(memory, '$.predictions.intents.before_reception.intent') = 'fallback'
    THEN 'V3'
    WHEN
      GET_JSON_OBJECT(memory, '$.predictions.intents.before_reception.intent') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.intents.before_reception.intent') <> 'fallback'
      OR GET_JSON_OBJECT(memory, '$.predictions.tags_v3') IS NOT NULL
      AND GET_JSON_OBJECT(memory, '$.predictions.tags_v3') <> 'null'
      AND id_pipeline = 'smarthelp_main'
    THEN 'before_reception'
    ELSE 'before_reception'
  END AS session_type,
  GET_JSON_OBJECT(memory, '$.business_rules.menu_taxonomies.selected_taxonomy') AS taxonomy,
  GET_JSON_OBJECT(memory, '$.predictions.tags_v4.theme') AS theme,
  GET_JSON_OBJECT(memory, '$.predictions.tags_v4.theme_details') theme_details,
  CASE
    WHEN id_pipeline = 'in_app_main' THEN 'Chat In-App'
    WHEN id_pipeline LIKE 'whatsapp%' THEN 'WhatsApp'
    WHEN id_pipeline IS NULL THEN 'Vazio'
    ELSE 'Outros'
  END AS channel,
  GET_JSON_OBJECT(memory, '$.experiments') AS experiments,
  year,
  month,
  day,
  NOW() AS ts_load
FROM
  datalake_greenseer.sessions
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) = 1

