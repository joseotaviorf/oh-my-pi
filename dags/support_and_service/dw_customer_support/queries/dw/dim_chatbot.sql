SELECT
  s.id_session AS sk_session,
  GET_JSON_OBJECT(s.memory, '$.basic.user.app_version') AS app_version,
  GET_JSON_OBJECT(s.memory, '$.business_rules.tags.added') AS tags,
  GET_JSON_OBJECT(s.memory, '$.business_rules.internal_chat.whatsapp_strategy') AS strategy,
  COALESCE(
      NULLIF(GET_JSON_OBJECT(s.memory,'$.business_rules.menu_taxonomies.selected_taxonomy'),''),
      NULLIF(GET_JSON_OBJECT(s.memory,'$.business_rules.confused_class.selected_theme_detail'),''),
      NULLIF(GET_JSON_OBJECT(s.memory,'$.business_rules.menu_theme_details.selected_theme_detail'),'')
    ) AS selected_taxonomy,
  GET_JSON_OBJECT(s.memory, '$.basic.session.context_message') AS context_message,
  GET_JSON_OBJECT(s.memory, '$.basic.flags') AS flags,
  s.current_state,
  CASE
    WHEN GET_JSON_OBJECT(s.memory, '$.experiments.experiment_taxonomies') IS NULL THEN 'before_reception' --BEFORE_RECEPTION
    WHEN coalesce(GET_JSON_OBJECT(s.memory, '$.experiments.experiment_taxonomies'), '') = 'control' THEN 'V3' --V3
    WHEN coalesce(GET_JSON_OBJECT(s.memory, '$.experiments.experiment_taxonomies'), '') = 'variant_observed' THEN 'V4' --V4
  END AS session_type,
  GET_JSON_OBJECT(s.memory, '$.business_rules.menu_taxonomies.selected_taxonomy') AS taxonomy,
  GET_JSON_OBJECT(s.memory, '$.predictions.tags_v4.theme') AS theme,
  GET_JSON_OBJECT(s.memory, '$.predictions.tags_v4.theme_details') theme_details,
  CASE
    WHEN s.id_pipeline = 'in_app_main' THEN 'Chat In-App'
    WHEN s.id_pipeline LIKE 'whatsapp%' THEN 'WhatsApp'
    WHEN s.id_pipeline IS NULL THEN 'Vazio'
    ELSE 'Outros'
  END AS channel,
  CASE 
    WHEN
      GET_JSON_OBJECT(s.memory, '$.business_rules.journey_flow.retention_emma.has_retention_response') IS NOT NULL
      OR GET_JSON_OBJECT(s.memory, '$.business_rules.journey_flow.retention_emma.emma_pipeline')= 'true' THEN 'experiment'
      ELSE 'control'
    END AS experimentAB,
  CASE 
    WHEN GET_JSON_OBJECT(s.memory, '$.business_rules.journey_flow.retention_emma.fallback') = 'true' THEN true
    ELSE false
  END AS experimentAB_fallback,
  s.year,
  s.month,
  s.day,
  NOW() AS ts_load
FROM datalake_greenseer.sessions AS s
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY s.id_session ORDER BY s.ts_updated DESC) = 1