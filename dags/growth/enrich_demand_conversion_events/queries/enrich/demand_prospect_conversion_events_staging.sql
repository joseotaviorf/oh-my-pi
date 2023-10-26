WITH conversion_events AS (
  -- SALE VISIT BOOKED
  SELECT
    NULL AS id_rent_flow,
    id_sale_flow,
    sk_event_type,
    "VISIT BOOKED" AS event_name,
    id_booking,
    id_offer,
    id_house,
    id_region,
    id_buyer AS id_prospect,
    id_seller AS id_owner,
    id_agent,
    "sale" AS business_context,
    dt_event,
    ts_event
  FROM
    datalake_sale_demand_events.sale_demand_events
  WHERE
    sk_event_type = 1
    AND dt_event BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  -- SALE OFFER SUBMITTED
  SELECT
    NULL AS id_rent_flow,
    id_sale_flow,
    sk_event_type,
    "OFFER SUBMITTED" AS event_name,
    id_booking,
    id_offer,
    id_house,
    id_region,
    id_buyer AS id_prospect,
    id_seller AS id_owner,
    id_agent,
    "sale" AS business_context,
    dt_event,
    ts_event
  FROM
    datalake_sale_demand_events.sale_demand_events
  WHERE
    sk_event_type = 3  
    AND dt_event BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  -- RENT VISIT BOOKED
  SELECT DISTINCT
    id_rent_flow,
    NULL AS id_sale_flow, 
    id_event_type AS sk_event_type,
    "VISIT BOOKED" AS event_name,
    id_booking,
    NULL AS id_offer,
    id_house,
    id_region,
    id_tenant_prospect AS id_prospect,
    id_owner,
    id_agent,
    "rent" AS business_context,
    DATE(ts_event) AS dt_event,
    ts_event
  FROM
     datalake_rent_demand_events.rent_demand_events
  WHERE
    id_event_type = 1
    AND id_event = id_booking
    AND DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  -- OFFER SUBMITED
  SELECT DISTINCT
    id_rent_flow,
    NULL AS id_sale_flow, 
    id_event_type AS sk_event_type,
    "OFFER SUBMITTED" AS event_name,
    id_booking,
    id_offer,
    id_house,
    id_region,
    id_tenant_prospect AS id_prospect,
    id_owner,
    id_agent,
    "rent" AS business_context,
    DATE(ts_event) AS dt_event,
    ts_event
  FROM
     datalake_rent_demand_events.rent_demand_events
  WHERE
    id_event_type = 3
    AND id_event = id_offer
    AND DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),

booking_attribution AS (
  SELECT 
      bce.id_rent_flow,
      bce.id_sale_flow, 
      bce.sk_event_type,
      bce.event_name,
      bce.id_booking,
      bce.id_offer,
      bce.id_house,
      bce.id_region,
      bce.id_prospect,
      bce.id_owner,
      bce.id_agent,
      bce.business_context,
      IF(acc.visit_code IS NOT NULL, acc.final_attribution_app_type, src.app_type) AS app_type,
      IF(acc.visit_code IS NOT NULL, acc.final_attribution_source, src.utm_source) AS utm_source,
      IF(acc.visit_code IS NOT NULL, acc.final_attribution_medium, src.utm_medium) AS utm_medium,
      IF(acc.visit_code IS NOT NULL, acc.final_attribution_campaign, src.utm_campaign) AS utm_campaign,
      IF(acc.visit_code IS NOT NULL, COALESCE(acc.final_attribution_branded, "Outro"), COALESCE(src.branded, "Outro")) AS branded,
      IF(acc.visit_code IS NOT NULL, acc.final_attribution_origin, 'old_attribution') AS final_attribution_origin,
      bce.dt_event,
      bce.ts_event
  FROM 
      conversion_events AS bce
  LEFT JOIN
    datalake_booking.booking AS b
      ON bce.id_booking = b.id
        AND DATE(b.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  LEFT JOIN datalake_amplitude_visit.amplitude_visit AS src
      ON b.code = src.id_visit
        AND DATE(src.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  LEFT JOIN datalake_tracked_events.attribution_cross_channel acc
      ON b.code = acc.visit_code
        AND acc.event_name IN ('visit_schedule_confirmed','debug_visit_schedule_confirmed')
        AND DATE(CONCAT_WS('-', acc.year, acc.month, acc.day)) BETWEEN DATE('{load_start_date}') AND  DATE('{load_end_date}')
  WHERE
      bce.sk_event_type = 1
),

sale_offer_attribution AS (
  SELECT
    soce.id_rent_flow,
    soce.id_sale_flow, 
    soce.sk_event_type,
    soce.event_name,
    soce.id_booking,
    soce.id_offer,
    soce.id_house,
    soce.id_region,
    soce.id_prospect,
    soce.id_owner,
    soce.id_agent,
    soce.business_context,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_app_type, sor.app_type) AS app_type,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_source, sor.utm_source) AS utm_source,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_medium, sor.utm_medium) AS utm_medium,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_campaign, sor.utm_campaign) AS utm_campaign,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_branded, sor.branded) AS branded,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_origin, 'old_attribution') AS final_attribution_origin,
    soce.dt_event,
    soce.ts_event
  FROM
    conversion_events AS soce
  LEFT JOIN
    datalake_amplitude_offer.sale_offer_raw_events AS sor
      ON soce.id_offer = sor.id_offer
        AND DATE(CONCAT_WS('-', sor.year, sor.month, sor.day)) BETWEEN DATE('{load_start_date}') AND  DATE('{load_end_date}')
  LEFT JOIN
    datalake_tracked_events.attribution_cross_channel AS acc
      ON sor.id_offer = acc.id_firestore
        AND acc.event_name = 'sale_offer_form_accepted' 
        AND DATE(CONCAT_WS('-', acc.year, acc.month, acc.day)) BETWEEN DATE('{load_start_date}') AND  DATE('{load_end_date}')
  WHERE
    soce.sk_event_type = 3
    AND soce.business_context = 'sale'
),

rent_offer_attribution AS (
  SELECT
    roce.id_rent_flow,
    roce.id_sale_flow, 
    roce.sk_event_type,
    roce.event_name,
    roce.id_booking,
    off.id_firestore AS id_offer,
    roce.id_house,
    roce.id_region,
    roce.id_prospect,
    roce.id_owner,
    roce.id_agent,
    roce.business_context,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_app_type, aos.app_type) AS app_type,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_source, aos.utm_source) AS utm_source,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_medium, aos.utm_medium) AS utm_medium,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_campaign, aos.utm_campaign) AS utm_campaign,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_branded, aos.branded) AS branded,
    IF(acc.id_firestore IS NOT NULL, acc.final_attribution_origin, 'old_attribution') AS final_attribution_origin,
    roce.dt_event,
    roce.ts_event
  FROM
    conversion_events AS roce
  LEFT JOIN
    datalake_offer.offer AS off
      ON roce.id_offer = off.id_offer_context
  LEFT JOIN
    datalake_amplitude_offer.offer_submitted_events AS aos
      ON off.id_firestore = aos.id_firestore
        AND DATE(CONCAT_WS('-', aos.year, aos.month, aos.day)) BETWEEN DATE('{load_start_date}') AND  DATE('{load_end_date}')
  LEFT JOIN 
    datalake_tracked_events.attribution_cross_channel AS acc
      ON aos.id_firestore = acc.id_firestore
        AND acc.event_name = 'offer_submitted'
        AND DATE(CONCAT_WS('-', acc.year, acc.month, acc.day)) BETWEEN DATE('{load_start_date}') AND  DATE('{load_end_date}')
  WHERE
    roce.sk_event_type = 3
    AND roce.business_context = 'rent'
),

legacy_data_talk_to_agent AS (
    SELECT
      (COALESCE(agent_id,10) || coalesce(a.tenant_id,0) || COALESCE(a.sk_house_listing,0) || unix_timestamp(first_message_ts)) AS id_talk_to_agent,
      IF(a.business_context = 'RENT', tenant_id || '_' || house_id, NULL) AS id_rent_flow,
      IF(a.business_context = 'SALE', tenant_id || '_' || house_id, NULL) AS id_sale_flow,
      99 AS sk_event_type,
      "TALK TO AGENT" AS event_name,
      NULL AS id_booking,
      NULL AS id_offer,
      INT(a.house_id) AS id_house,
      h.id_region,
      INT(a.tenant_id) AS id_prospect,
      h.id_user AS id_owner,
      a.agent_id AS id_agent,
      LOWER(a.business_context) AS business_context,
      a.app_type,
      a.utm_medium,
      a.utm_source,
      a.utm_campaign,
      a.branded,
      DATE(a.first_message_ts) AS dt_event,
      TO_TIMESTAMP(a.first_message_ts) AS ts_event
    FROM
      datalake_talk_to_agent.talk_to_agent AS a
    INNER JOIN
      datalake_ebdb_clean.house AS h
        ON h.id = a.house_id
    WHERE
      DATE(a.first_message_ts) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),

events_with_attribution AS (
  SELECT
    INT(DATE_FORMAT(dt_event,'yyyyMMdd')) AS id_event_date,
    id_rent_flow,
    id_sale_flow, 
    sk_event_type,
    event_name,
    id_booking,
    id_offer,
    NULL AS id_talk_to_agent,
    id_house,
    id_region,
    id_prospect,
    id_owner,
    id_agent,
    business_context,
    app_type,
    utm_medium,
    utm_source,
    utm_campaign,
    branded,
    dt_event,
    ts_event
  FROM
    booking_attribution
  UNION ALL
  SELECT
    INT(DATE_FORMAT(dt_event,'yyyyMMdd')) AS id_event_date,
    id_rent_flow,
    id_sale_flow, 
    sk_event_type,
    event_name,
    id_booking,
    id_offer,
    NULL AS id_talk_to_agent,
    id_house,
    id_region,
    id_prospect,
    id_owner,
    id_agent,
    business_context,
    app_type,
    utm_medium,
    utm_source,
    utm_campaign,
    branded,
    dt_event,
    ts_event
  FROM
    sale_offer_attribution
  UNION ALL
  SELECT
    INT(DATE_FORMAT(dt_event,'yyyyMMdd')) AS id_event_date,
    id_rent_flow,
    id_sale_flow, 
    sk_event_type,
    event_name,
    id_booking,
    id_offer,
    NULL AS id_talk_to_agent,
    id_house,
    id_region,
    id_prospect,
    id_owner,
    id_agent,
    business_context,
    app_type,
    utm_medium,
    utm_source,
    utm_campaign,
    branded,
    dt_event,
    ts_event
  FROM
    rent_offer_attribution
  UNION ALL
  SELECT
    INT(DATE_FORMAT(dt_event,'yyyyMMdd')) AS id_event_date,
    id_rent_flow,
    id_sale_flow, 
    sk_event_type,
    event_name,
    id_booking,
    id_offer,
    id_talk_to_agent,
    id_house,
    id_region,
    id_prospect,
    id_owner,
    id_agent,
    business_context,
    app_type,
    utm_medium,
    utm_source,
    utm_campaign,
    branded,
    dt_event,
    ts_event
  FROM
    legacy_data_talk_to_agent
),

last_sk_values AS (
    SELECT
        COALESCE(MAX(sk_demand_prospect_conversion_event), 0) AS max_sk_demand_prospect_conversion_event
    FROM
        datalake_demand_flows.demand_prospect_conversion_events
)

SELECT
  COALESCE(
      f.sk_demand_prospect_conversion_event,
      lsv.max_sk_demand_prospect_conversion_event + MONOTONICALLY_INCREASING_ID() + 1
  ) AS sk_demand_prospect_conversion_event,
  e.id_event_date,
  e.id_rent_flow,
  e.id_sale_flow, 
  e.sk_event_type,
  e.event_name,
  e.id_booking,
  e.id_offer,
  e.id_talk_to_agent,
  e.id_house,
  e.id_region,
  e.id_prospect,
  e.id_owner,
  e.id_agent,
  e.business_context,
  b.user_sale_booking_creator AS booking_creator,
  b.first_update_source AS product_origin,
  b.is_3p_demand,
  e.app_type,
  e.utm_medium,
  e.utm_source,
  e.utm_campaign,
  e.branded,
  r.country_code,
  e.dt_event,
  e.ts_event,
  YEAR(e.dt_event) AS year,
  MONTH(e.dt_event) AS month,
  DAY(e.dt_event) AS day
FROM
  events_with_attribution AS e
LEFT JOIN
  datalake_booking.booking AS b
    ON e.id_booking = b.id
    AND DATE(b.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
LEFT JOIN
  datalake_region.region AS r
    ON e.id_region = r.id
CROSS JOIN
  last_sk_values AS lsv
LEFT JOIN
  datalake_demand_flows.demand_prospect_conversion_events AS f
    ON e.id_event_date = f.id_event_date
      AND e.sk_event_type = f.sk_event_type
      AND (
          (e.sk_event_type = 1 AND e.id_booking = f.id_booking)
          OR (e.sk_event_type = 3 AND e.id_offer = f.id_offer)
          OR (e.sk_event_type = 99 AND e.id_talk_to_agent = f.id_talk_to_agent)
      )