WITH adhoc_rules AS (
  SELECT
    ui.id AS id_top_of_funnel_event,
    ui.id_tof_user,
    ui.id_house,
    ui.sk_region,
    CASE 
      WHEN utm_campaign IS NULL
        AND utm_source IS NULL
        AND utm_medium IS NULL
        AND app_type IS NULL
      THEN "lost.los.lostra.lostra.l.losttracking.losttracking"
      WHEN utm_campaign IS NULL
        AND utm_source IS NULL
        AND utm_medium IS NULL
        AND app_type IS NOT NULL
      THEN "na.acq.org.na.d.direct.na"
    END AS utm_adhoc_rule,
    'SelfServiceWeb' AS origin,
    'SelfService' AS operation_channel, 
    CASE
      WHEN ui.app_type IS NULL THEN "Lost Tracking"
      WHEN LOWER(ui.app_type) LIKE '%android%' THEN 'App Android'
      WHEN LOWER(ui.app_type) LIKE '%ios%' THEN 'App iOS'
      WHEN LOWER(ui.app_type) LIKE '%web_desktop%' THEN 'Web Desktop'
      WHEN LOWER(ui.app_type) LIKE '%web_mobile%' THEN 'Web Mobile'
      ELSE "Other"
    END AS platform,
    ui.app_type,
    '' AS content_page,
    ui.utm_campaign,
    ui.utm_source,
    ui.utm_medium,
    ui.utm_content,
    ui.utm_term,
    ui.business_context,
    ui.entrance_uri,
    ui.referrer,
    ui.branded,
    ui.dt_event,
    ui.ts_event,
    ui.year,
    ui.month,
    ui.day
  FROM
    datalake_top_of_funnel_demand.user_interactions AS ui
  WHERE
    ui.dt_event BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
media_setup_ids AS (
  SELECT
    tof.id_top_of_funnel_event,
    tof.id_tof_user,
    tof.id_house,
    tof.sk_region,
    tof.utm_adhoc_rule AS media_setup_from_adhoc,
    concat_ws('.', slice(split(tof.utm_campaign, '[.]'), 2, 7)) AS media_setup_from_naming_convention,
    concat_ws('.', slice(split(ef.correct_utm_campaign, '[.]'), 2, 7)) AS media_setup_from_exception_flow,
    dict.naming_convention_sufix AS media_setup_from_dictionary,
    tof.utm_adhoc_rule,
    tof.utm_campaign, 
    tof.utm_medium,
    tof.utm_source,
    tof.utm_content,
    tof.utm_term,
    tof.origin,
    tof.operation_channel,
    tof.platform,
    tof.app_type,
    tof.content_page,
    tof.business_context,
    tof.entrance_uri,
    tof.referrer,
    tof.branded,
    tof.dt_event,
    tof.ts_event,
    tof.year,
    tof.month,
    tof.day
  FROM
    adhoc_rules AS tof
  LEFT JOIN 
    datalake_growth_taxonomy.unified_taxonomy_dictionary AS dict
        ON COALESCE(SF_NORMALIZE_STRING(tof.utm_campaign),0) = COALESCE(LOWER(dict.utm_campaign),0)
        AND COALESCE(SF_NORMALIZE_STRING(tof.utm_source),0) = COALESCE(LOWER(dict.utm_source),0)
        AND COALESCE(SF_NORMALIZE_STRING(tof.utm_medium),0) = COALESCE(LOWER(dict.utm_medium),0)
  LEFT JOIN
    datalake_gsheets_clean.taxonomy_demand_exception_flow AS ef
        ON LOWER(tof.utm_campaign) = LOWER(ef.utm_campaign)
        AND LOWER(tof.utm_source) = LOWER(ef.utm_source)
        AND LOWER(tof.utm_medium) = LOWER(ef.utm_medium)
),
final_media_setup as (
SELECT
  id_top_of_funnel_event,
  id_tof_user,
  id_house,
  sk_region,
  media_setup_from_adhoc,
  media_setup_from_dictionary,
  media_setup_from_exception_flow,
  media_setup_from_naming_convention,
  CASE
    WHEN media_setup_from_adhoc IS NOT NULL THEN media_setup_from_adhoc
    WHEN media_setup_from_exception_flow IS NOT NULL AND media_setup_from_exception_flow <> '' THEN media_setup_from_exception_flow
    WHEN media_setup_from_dictionary IS NOT NULL THEN media_setup_from_dictionary
    WHEN media_setup_from_naming_convention IS NOT NULL THEN media_setup_from_naming_convention
  END AS naming_convention_sufix,
  CASE
    WHEN media_setup_from_adhoc IS NOT NULL THEN "adhoc rule"
    WHEN media_setup_from_exception_flow IS NOT NULL AND media_setup_from_exception_flow <> '' THEN "exception flow"
    WHEN media_setup_from_dictionary IS NOT NULL THEN "dictionary"
    WHEN media_setup_from_naming_convention IS NOT NULL THEN "naming convention"
  END AS naming_convention_sufix_origin,
  utm_adhoc_rule,
  utm_campaign, 
  utm_medium,
  utm_source,
  utm_content,
  utm_term,
  app_type,
  content_page,
  origin,
  operation_channel,
  platform,
  business_context,
  entrance_uri,
  referrer,
  branded,
  dt_event,
  ts_event,
  year,
  month,
  day
FROM
  media_setup_ids
)
SELECT
  fms.id_top_of_funnel_event,
  fms.id_tof_user,
  fms.id_house,
  fms.sk_region,
  fms.naming_convention_sufix,
  fms.naming_convention_sufix_origin,
  fms.utm_adhoc_rule,
  fms.utm_campaign,
  fms.utm_medium,
  fms.utm_source,
  fms.utm_content,
  fms.utm_term,
  fms.app_type,
  fms.content_page,
  fms.origin,
  fms.operation_channel,
  fms.platform,
  fms.business_context,
  fms.entrance_uri,
  fms.referrer,
  fms.branded,
  ms.behavior_type,
  ms.campaign_business_context,
  ms.campaign_strategy_intent,
  ms.campaign_landing_page,
  ms.funnel_side,
  ms.medium,
  ms.source,
  fms.dt_event,
  fms.ts_event,
  fms.year,
  fms.month,
  fms.day
FROM 
  final_media_setup fms 
    LEFT JOIN 
      datalake_growth_taxonomy.media_setup ms
      ON fms.naming_convention_sufix = ms.naming_convention_sufix  