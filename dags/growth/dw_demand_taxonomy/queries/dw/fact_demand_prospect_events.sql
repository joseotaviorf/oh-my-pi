SELECT
  id_prospect_event AS sk_prospect_event,
  id_prospect AS sk_prospect,
  id_media_setup AS sk_media_setup,
  id_rent_flow AS sk_rent_flow,
  id_sale_flow AS sk_sale_flow, 
  id_booking AS sk_booking,
  id_offer AS sk_offer,
  id_talk_to_agent AS sk_talk_to_agent,
  id_house AS sk_house,
  id_region AS sk_region,
  id_owner AS sk_owner,
  id_agent AS sk_agent,
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
  id_event_date AS sk_event_date,
  ts_event,
  year,
  month,
  day
FROM 
  datalake_demand_flows.prospect_daily_results
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}