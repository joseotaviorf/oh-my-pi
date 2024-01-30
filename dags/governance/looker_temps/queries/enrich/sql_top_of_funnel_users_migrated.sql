SELECT DISTINCT
  ui.id,
  ui.dt_event,
  ui.id_tof_user,
  fui.id_tof_user AS id_first_interaction,
  ui.id_house,
  ui.sk_region,
  LOWER(ui.business_context) AS business_context,
  ui.mkt_category,
  ui.mkt_flow,
  ui.mkt_completion,
  ui.mkt_origin,
  ui.mkt_channel,
  ui.mkt_medium,
  ui.mkt_source,
  ui.mkt_platform,
  ui.app_type,
  ui.utm_source,
  ui.utm_medium,
  ui.utm_campaign,
  ui.utm_content,
  ui.utm_term,
  ui.branded
FROM datalake_top_of_funnel_demand.user_interactions AS ui
LEFT JOIN datalake_top_of_funnel_demand.first_user_interaction AS fui
  ON ui.id = fui.id