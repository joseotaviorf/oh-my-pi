WITH adhoc_rules AS (
  SELECT
    dpce.id_demand_prospect_conversion_event,
    dpce.id_prospect,
    dpce.business_context,
    dpce.id_event_type,
    dpce.event_name,
    CASE 
      WHEN dpce.product_origin = 'Corretores'
      THEN "na.acq.org.na.d.direct.na"
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
    dpce.id_rent_flow,
    dpce.id_sale_flow, 
    dpce.id_booking,
    dpce.id_offer,
    dpce.id_talk_to_agent,
    dpce.id_house,
    dpce.id_region,
    dpce.id_owner,
    dpce.id_agent,
    dpce.utm_campaign, 
    dpce.utm_medium,
    dpce.utm_source,
    dpce.utm_term,
    dpce.app_type,
    dpce.booking_creator,
    dpce.product_origin,
    dpce.is_3p_demand,
    CASE
      WHEN dpce.booking_creator IS NULL AND dpce.id_booking IS NOT NULL THEN "Lost Tracking"
      WHEN dpce.booking_creator IS NULL AND dpce.id_booking IS NULL THEN "SelfService"
      WHEN dpce.booking_creator = 'SelfService' THEN 'SelfService' 
      WHEN dpce.booking_creator = 'Admin/CX' THEN 'CX'
      ELSE dpce.booking_creator 
    END AS operation_channel,
    CASE
      WHEN dpce.is_3p_demand = TRUE THEN 'Rede'
      WHEN dpce.booking_creator = 'Agent' AND dpce.is_3p_demand = FALSE THEN 'Agent'
      ELSE 'NA' -- TQC
    END AS referral_type,
    CASE 
      WHEN dpce.product_origin IS NULL THEN 'Lost Tracking'
      ELSE dpce.product_origin
    END AS origin,
    CASE
      WHEN dpce.app_type IS NULL THEN "Lost Tracking"
      WHEN LOWER(dpce.app_type) LIKE '%android%' THEN 'App Android'
      WHEN LOWER(dpce.app_type) LIKE '%ios%' THEN 'App iOS'
      WHEN LOWER(dpce.app_type) LIKE '%web_desktop%' THEN 'Web Desktop'
      WHEN LOWER(dpce.app_type) LIKE '%web_mobile%' THEN 'Web Mobile'
      ELSE "Other"
    END AS platform,
    '' AS content_page,
    dpce.ts_event,
    dpce.year,
    dpce.month,
    dpce.day
  FROM
    datalake_demand_flows.demand_prospect_conversion_events AS dpce
  WHERE 
    DATE(dpce.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')  
),

media_setup_ids AS (
  SELECT
    dpce.id_demand_prospect_conversion_event,
    dpce.id_prospect,
    dpce.business_context,
    dpce.id_event_type,
    dpce.event_name,
    dpce.utm_adhoc_rule AS media_setup_from_adhoc,
    concat_ws('.', slice(split(dpce.utm_campaign, '[.]'), 2, 7)) AS media_setup_from_naming_convention,
    concat_ws('.', slice(split(ef.correct_utm_campaign, '[.]'), 2, 7)) AS media_setup_from_exception_flow,
    dict.naming_convention_sufix AS media_setup_from_dictionary,
    dpce.id_rent_flow,
    dpce.id_sale_flow, 
    dpce.id_booking,
    dpce.id_offer,
    dpce.id_talk_to_agent,
    dpce.id_house,
    dpce.id_region,
    dpce.id_owner,
    dpce.id_agent,
    dpce.utm_adhoc_rule,
    dpce.utm_campaign, 
    dpce.utm_medium,
    dpce.utm_source,
    dpce.utm_term,
    dpce.app_type,
    dpce.booking_creator,
    dpce.product_origin,
    dpce.is_3p_demand,
    dpce.operation_channel,
    dpce.referral_type,
    dpce.origin,
    dpce.platform,
    dpce.content_page,
    dpce.ts_event,
    dpce.year,
    dpce.month,
    dpce.day
  FROM
    adhoc_rules AS dpce
  LEFT JOIN
    datalake_growth_taxonomy.unified_taxonomy_dictionary AS dict
      ON COALESCE(SF_NORMALIZE_STRING(dpce.utm_campaign),0) = COALESCE(LOWER(dict.utm_campaign),0)
      AND COALESCE(SF_NORMALIZE_STRING(dpce.utm_source),0) = COALESCE(LOWER(dict.utm_source),0)
      AND COALESCE(SF_NORMALIZE_STRING(dpce.utm_medium),0) = COALESCE(LOWER(dict.utm_medium),0)
  LEFT JOIN
    datalake_gsheets_clean.taxonomy_demand_exception_flow AS ef
      ON LOWER(dpce.utm_campaign) = LOWER(ef.utm_campaign)
      AND LOWER(dpce.utm_source) = LOWER(ef.utm_source)
      AND LOWER(dpce.utm_medium) = LOWER(ef.utm_medium)
)

SELECT
  id_demand_prospect_conversion_event,
  id_prospect,
  business_context,
  id_event_type,
  event_name,
  media_setup_from_adhoc,
  media_setup_from_dictionary,
  media_setup_from_exception_flow,
  media_setup_from_naming_convention,
  CASE
    WHEN media_setup_from_adhoc IS NOT NULL THEN media_setup_from_adhoc
    WHEN media_setup_from_dictionary IS NOT NULL THEN media_setup_from_dictionary
    WHEN media_setup_from_exception_flow IS NOT NULL THEN media_setup_from_exception_flow
    WHEN media_setup_from_naming_convention IS NOT NULL THEN media_setup_from_naming_convention
  END AS naming_convention_sufix,
  CASE
    WHEN media_setup_from_adhoc IS NOT NULL THEN "adhoc rule"
    WHEN media_setup_from_dictionary IS NOT NULL THEN "dictionary"
    WHEN media_setup_from_exception_flow IS NOT NULL THEN "exception flow"
    WHEN media_setup_from_naming_convention IS NOT NULL THEN "naming convention"
  END AS naming_convention_sufix_origin,
  id_rent_flow,
  id_sale_flow, 
  id_booking,
  id_offer,
  id_talk_to_agent,
  id_house,
  id_region,
  id_owner,
  id_agent,
  utm_adhoc_rule,
  utm_campaign, 
  utm_medium,
  utm_source,
  utm_term,
  app_type,
  booking_creator,
  product_origin,
  is_3p_demand,
  operation_channel,
  referral_type,
  origin,
  platform,
  content_page,
  ts_event,
  year,
  month,
  day
FROM
  media_setup_ids