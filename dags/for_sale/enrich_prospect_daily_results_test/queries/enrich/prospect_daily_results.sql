WITH prospect_status_events AS (
  SELECT
    tps.id_demand_prospect_conversion_event,
    tps.id_tenant_prospect AS id_prospect,
    'rent' AS business_context,
    'CONVERSION' AS event_type,
    tps.prospect_event_name AS event_name,
    tps.status_trigger_event_name AS event_detail,
    tps.ts_status_started AS ts_event,
    tps.year,
    tps.month,
    tps.day
  FROM
    datalake_demand_conversion_events_test.tenant_prospect_status AS tps
  WHERE 
    DATE(tps.ts_status_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')   
  UNION ALL 
  SELECT
    bps.id_demand_prospect_conversion_event,
    bps.id_buyer_prospect AS id_prospect,
    'sale' AS business_context,
    'CONVERSION' AS event_type,
    bps.prospect_event_name AS event_name,
    bps.status_trigger_event_name AS event_detail,
    bps.ts_status_started AS ts_event,
    bps.year,
    bps.month,
    bps.day
  FROM
    datalake_demand_conversion_events_test.buyer_prospect_status AS bps
  WHERE 
    DATE(bps.ts_status_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')   
),

prospect_results AS (
  SELECT
    pcr.id_demand_prospect_conversion_event,
    pse.id_prospect,
    pse.business_context,
    pse.event_type,
    pse.event_name,
    pse.event_detail,
    pcr.naming_convention_sufix,
    pcr.id_rent_flow,
    pcr.id_sale_flow, 
    pcr.id_booking,
    pcr.id_offer,
    pcr.id_talk_to_agent,
    pcr.id_house,
    pcr.id_region,
    pcr.id_owner,
    pcr.id_agent,
    pcr.product_origin,
    pcr.app_type,
    pcr.origin,
    pcr.platform,
    pcr.content_page,
    pcr.operation_channel,
    pcr.referral_type,
    pcr.utm_campaign,
    pcr.utm_medium,
    pcr.utm_source,
    pcr.utm_term,
    pcr.utm_content,
    pcr.entrance_uri,
    pse.ts_event,
    pse.year,
    pse.month,
    pse.day
  FROM
    prospect_status_events AS pse
  LEFT JOIN
    datalake_demand_conversion_events_test.prospect_results AS pcr
      ON pse.id_demand_prospect_conversion_event = pcr.id_demand_prospect_conversion_event
  UNION ALL
  SELECT
    pcr.id_demand_prospect_conversion_event,
    pcr.id_prospect,
    pcr.business_context,
    'FLOW' AS event_type,
    pcr.event_name,
    NULL AS event_detail,
    pcr.naming_convention_sufix,
    pcr.id_rent_flow,
    pcr.id_sale_flow, 
    pcr.id_booking,
    pcr.id_offer,
    pcr.id_talk_to_agent,
    pcr.id_house,
    pcr.id_region,
    pcr.id_owner,
    pcr.id_agent,
    pcr.product_origin,
    pcr.app_type,
    pcr.origin,
    pcr.platform,
    pcr.content_page,
    pcr.operation_channel,
    pcr.referral_type,
    pcr.utm_campaign,
    pcr.utm_medium,
    pcr.utm_source,
    pcr.utm_term,
    pcr.utm_content,
    pcr.entrance_uri,
    pcr.ts_event,
    pcr.year,
    pcr.month,
    pcr.day 
  FROM
    datalake_demand_conversion_events_test.prospect_results AS pcr
  WHERE 
    DATE(pcr.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')    
  QUALIFY   
    ROW_NUMBER() OVER(PARTITION BY id_demand_prospect_conversion_event ORDER BY ts_event ASC) = 1 
)

SELECT
  MONOTONICALLY_INCREASING_ID() AS id_prospect_event,
  id_demand_prospect_conversion_event,
  id_prospect,
  business_context,
  event_type,
  event_name,
  event_detail,
  naming_convention_sufix,
  id_rent_flow,
  id_sale_flow, 
  id_booking,
  id_offer,
  id_talk_to_agent,
  id_house,
  id_region,
  id_owner,
  id_agent,
  product_origin,
  app_type,
  origin,
  platform,
  content_page,
  operation_channel,
  referral_type,
  utm_campaign,
  utm_medium,
  utm_source,
  utm_term,
  utm_content,
  entrance_uri,
  INT(DATE_FORMAT(ts_event,'yyyyMMdd')) AS id_event_date,
  ts_event,
  year,
  month,
  day
FROM
  prospect_results