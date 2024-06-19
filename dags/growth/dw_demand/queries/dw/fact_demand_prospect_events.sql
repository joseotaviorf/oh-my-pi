WITH prospect_results AS (
SELECT
  id_prospect_event AS sk_prospect_event,
  id_prospect AS sk_prospect,
  id_rent_flow AS sk_rent_flow,
  id_sale_flow AS sk_sale_flow,
  COALESCE(id_rent_flow, id_sale_flow) AS sk_flow,
  id_booking AS sk_booking,
  id_offer AS sk_offer,
  id_talk_to_agent AS sk_talk_to_agent,
  id_house AS sk_house,
  id_region AS sk_region,
  id_owner AS sk_owner,
  id_agent AS sk_agent,
  naming_convention_sufix,
  business_context,
  event_type,
  event_name,
  event_detail,
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
  ROW_NUMBER() OVER(PARTITION BY COALESCE(id_rent_flow, id_sale_flow), event_type, business_context ORDER BY ts_event ASC) AS flow_order,
  id_event_date AS sk_event_date,
  ts_event,
  year,
  month,
  day,
  NOW() AS ts_load
FROM 
  datalake_demand_flows.prospect_daily_results
)
SELECT
  *
FROM prospect_results
WHERE
    DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND DATE(ts_event) <= CURRENT_DATE()