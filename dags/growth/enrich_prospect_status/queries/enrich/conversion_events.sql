WITH
  union_events AS (
    -- SALE VISIT BOOKED
    SELECT
      NULL AS id_rent_flow,
      id_sale_flow,
      NULL AS id_talk_to_agent,
      sk_event_type AS id_event_type,
      "VISIT BOOKED" AS event_name,
      id_booking,
      NULL AS id_offer,
      id_house,
      id_region,
      id_buyer AS id_prospect,
      id_seller AS id_owner,
      id_agent,
      "sale" AS business_context,
      sale_type,
      dt_event,
      ts_event
    FROM
      datalake_sale_demand_events.sale_demand_events
    WHERE
      sk_event_type = 1
      AND id_buyer != id_seller
      AND dt_event BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    -- SALE OFFER SUBMITTED
    SELECT
      NULL AS id_rent_flow,
      id_sale_flow,
      NULL AS id_talk_to_agent,
      sk_event_type AS id_event_type,
      "OFFER SUBMITTED" AS event_name,
      NULL AS id_booking,
      id_offer,
      id_house,
      id_region,
      id_buyer AS id_prospect,
      id_seller AS id_owner,
      id_agent,
      "sale" AS business_context,
      sale_type,
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
      NULL AS id_talk_to_agent,
      id_event_type,
      "VISIT BOOKED" AS event_name,
      id_booking,
      NULL AS id_offer,
      id_house,
      id_region,
      id_tenant_prospect AS id_prospect,
      id_owner,
      id_agent,
      "rent" AS business_context,
      CAST(NULL AS STRING) AS sale_type,
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
      NULL AS id_talk_to_agent,
      id_event_type,
      "OFFER SUBMITTED" AS event_name,
      NULL AS id_booking,
      id_offer,
      id_house,
      id_region,
      id_tenant_prospect AS id_prospect,
      id_owner,
      id_agent,
      "rent" AS business_context,
      CAST(NULL AS STRING) AS sale_type,
      DATE(ts_event) AS dt_event,
      ts_event
    FROM
      datalake_rent_demand_events.rent_demand_events
    WHERE
      id_event_type = 3
      AND id_event = id_offer
      AND DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
      IF (a.business_context = 'RENT', tenant_id || '_' || house_id, NULL) AS id_rent_flow,
      IF (a.business_context = 'SALE', tenant_id || '_' || house_id, NULL) AS id_sale_flow,
      (
        COALESCE(agent_id, 10) || COALESCE(a.tenant_id, 0) || COALESCE(a.sk_house_listing, 0) || UNIX_TIMESTAMP(first_message_ts)
      ) AS id_talk_to_agent,
      99 AS id_event_type,
      "TALK TO AGENT" AS event_name,
      NULL AS id_booking,
      NULL AS id_offer,
      INT(a.house_id) AS id_house,
      h.id_region,
      INT(a.tenant_id) AS id_prospect,
      h.id_user AS id_owner,
      a.agent_id AS id_agent,
      LOWER(a.business_context) AS business_context,
      CASE
        WHEN LOWER(a.business_context) = 'sale' THEN lst.sale_type
      END AS sale_type,
      DATE(a.first_message_ts) AS dt_event,
      TO_TIMESTAMP(a.first_message_ts) AS ts_event
    FROM
      datalake_talk_to_agent.talk_to_agent AS a
    INNER JOIN
      datalake_ebdb_clean.house AS h
        ON h.id = a.house_id
    LEFT JOIN
      datalake_sale_primary_market.listing_sale_type AS lst
        ON lst.id_house = INT(a.house_id)
    WHERE
      DATE(a.first_message_ts) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  )
SELECT
  MD5(
    CONCAT(
      ts_event,
      id_event_type,
      business_context,
      COALESCE(id_booking, -1),
      COALESCE(id_offer, -1),
      COALESCE(id_talk_to_agent, -1),
      id_prospect,
      id_house
    )
  ) AS id_demand_prospect_conversion_event,
  id_rent_flow,
  id_sale_flow,
  id_talk_to_agent,
  id_event_type,
  id_booking,
  id_offer,
  id_house,
  id_region,
  id_prospect,
  id_owner,
  id_agent,
  event_name,
  business_context,
  sale_type,
  CAST(dt_event AS TIMESTAMP) AS dt_event,
  ts_event,
  YEAR(dt_event) AS year,
  MONTH(dt_event) AS month,
  DAY(dt_event) AS day
FROM
  union_events
