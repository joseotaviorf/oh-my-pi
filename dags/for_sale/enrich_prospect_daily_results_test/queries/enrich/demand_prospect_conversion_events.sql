WITH conversion_events_filtered AS (
  SELECT
    id_rent_flow,
    id_sale_flow,
    id_event_type,
    event_name,
    id_booking,
    id_offer,
    id_house,
    id_region,
    id_prospect,
    id_owner,
    id_agent,
    id_talk_to_agent,
    business_context,
    dt_event,
    ts_event
  FROM
    datalake_demand_conversion_events_test.conversion_events
  WHERE
    dt_event BETWEEN DATE('2025-01-21') AND DATE('2025-02-06')
),
booking_attribution AS (
  SELECT
    bce.id_rent_flow,
    bce.id_sale_flow,
    bce.id_event_type,
    bce.event_name,
    bce.id_booking,
    bce.id_offer,
    bce.id_house,
    bce.id_region,
    bce.id_prospect,
    bce.id_owner,
    bce.id_agent,
    bce.business_context,
    IF(
      acc.visit_code IS NOT NULL,
      acc.final_attribution_app_type,
      src.app_type
    ) AS app_type,
    IF(
      acc.visit_code IS NOT NULL,
      acc.final_attribution_source,
      src.utm_source
    ) AS utm_source,
    IF(
      acc.visit_code IS NOT NULL,
      acc.final_attribution_medium,
      src.utm_medium
    ) AS utm_medium,
    IF(
      acc.visit_code IS NOT NULL,
      acc.final_attribution_campaign,
      src.utm_campaign
    ) AS utm_campaign,
    IF(
      acc.visit_code IS NOT NULL,
      acc.final_attribution_term,
      src.utm_term
    ) AS utm_term,
    IF(
      acc.visit_code IS NOT NULL,
      acc.final_attribution_content,
      src.utm_content
    ) AS utm_content,
    IF(
      acc.visit_code IS NOT NULL,
      acc.final_attribution_entrance_uri,
      src.entrance_uri
    ) AS entrance_uri,
    IF(
      acc.visit_code IS NOT NULL,
      COALESCE(acc.final_attribution_branded, "Outro"),
      COALESCE(src.branded, "Outro")
    ) AS branded,
    IF(
      acc.visit_code IS NOT NULL,
      acc.final_attribution_origin,
      'old_attribution'
    ) AS final_attribution_origin,
    bce.dt_event,
    bce.ts_event
  FROM
    conversion_events_filtered AS bce
  LEFT JOIN 
    datalake_booking.booking AS b 
      ON bce.id_booking = b.id
      AND DATE(b.ts_created) BETWEEN DATE('2025-01-21')
      AND DATE('2025-02-06')
  LEFT JOIN 
    datalake_amplitude_visit.amplitude_visit AS src 
      ON b.code = src.id_visit
      AND DATE(src.ts_event) BETWEEN DATE('2025-01-21')
      AND DATE('2025-02-06')
  LEFT JOIN 
    datalake_tracked_events.attribution_cross_channel acc 
      ON b.code = acc.visit_code
      AND acc.event_name IN (
        'visit_schedule_confirmed',
        'debug_visit_schedule_confirmed'
      )
      AND DATE(acc.ts_event) BETWEEN DATE('2025-01-21') AND DATE('2025-02-06')
  WHERE
    bce.id_event_type = 1
),
sale_offer_from_amplitude AS (
  SELECT
    id_user,
    id_house,
    id_offer,
    app_type,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    entrance_uri,
    branded,
    ts_event,
    year,
    month,
    day
  FROM
    datalake_amplitude_offer.sale_offer_raw_events
  QUALIFY 
    ROW_NUMBER() OVER(
      PARTITION BY id_offer
      ORDER BY
        ts_event ASC
    ) = 1
),
sale_offer_attribution AS (
  SELECT
    soce.id_rent_flow,
    soce.id_sale_flow,
    soce.id_event_type,
    soce.event_name,
    soce.id_booking,
    soce.id_offer,
    soce.id_house,
    soce.id_region,
    soce.id_prospect,
    soce.id_owner,
    soce.id_agent,
    soce.business_context,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_app_type,
      sor.app_type
    ) AS app_type,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_source,
      sor.utm_source
    ) AS utm_source,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_medium,
      sor.utm_medium
    ) AS utm_medium,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_campaign,
      sor.utm_campaign
    ) AS utm_campaign,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_term,
      sor.utm_term
    ) AS utm_term,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_content,
      sor.utm_content
    ) AS utm_content,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_entrance_uri,
      sor.entrance_uri
    ) AS entrance_uri,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_branded,
      sor.branded
    ) AS branded,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_origin,
      'old_attribution'
    ) AS final_attribution_origin,
    soce.dt_event,
    soce.ts_event
  FROM
    conversion_events_filtered AS soce
    LEFT JOIN 
      sale_offer_from_amplitude AS sor 
        ON soce.id_offer = sor.id_offer
    AND (
      soce.id_prospect = sor.id_user
      OR soce.id_house = sor.id_house
    )
    AND sor.ts_event BETWEEN DATE('2025-01-21')
    AND DATE('2025-02-06')
    LEFT JOIN 
      datalake_tracked_events.attribution_cross_channel AS acc 
        ON sor.id_offer = acc.id_firestore
    AND acc.event_name = 'sale_offer_form_accepted'
    AND DATE(acc.ts_event) BETWEEN DATE('2025-01-21')
    AND DATE('2025-02-06')
  WHERE
    soce.id_event_type = 3
    AND soce.business_context = 'sale'
),
rent_offer_from_amplitude AS (
  SELECT
    id_user,
    id_house,
    id_firestore,
    app_type,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    entrance_uri,
    branded,
    ts_event,
    year,
    month,
    day
  FROM
    datalake_amplitude_offer.offer_submitted_events
  QUALIFY 
    ROW_NUMBER() OVER(
      PARTITION BY id_firestore
      ORDER BY
        ts_event ASC
    ) = 1
),
rent_offer_attribution AS (
  SELECT
    roce.id_rent_flow,
    roce.id_sale_flow,
    roce.id_event_type,
    roce.event_name,
    roce.id_booking,
    roce.id_offer,
    off.id_firestore,
    roce.id_house,
    roce.id_region,
    roce.id_prospect,
    roce.id_owner,
    roce.id_agent,
    roce.business_context,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_app_type,
      aos.app_type
    ) AS app_type,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_source,
      aos.utm_source
    ) AS utm_source,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_medium,
      aos.utm_medium
    ) AS utm_medium,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_campaign,
      aos.utm_campaign
    ) AS utm_campaign,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_term,
      aos.utm_term
    ) AS utm_term,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_content,
      aos.utm_content
    ) AS utm_content,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_entrance_uri,
      aos.entrance_uri
    ) AS entrance_uri,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_branded,
      aos.branded
    ) AS branded,
    IF(
      acc.id_firestore IS NOT NULL,
      acc.final_attribution_origin,
      'old_attribution'
    ) AS final_attribution_origin,
    roce.dt_event,
    roce.ts_event
  FROM
    conversion_events_filtered AS roce
    LEFT JOIN 
      datalake_offer.offer AS off 
        ON (roce.id_offer = off.id_offer_context)
    LEFT JOIN 
      rent_offer_from_amplitude AS aos 
        ON (off.id_firestore = aos.id_firestore)
        AND (
          (roce.id_prospect = aos.id_user)
          OR (roce.id_house = aos.id_house)
        )
        AND (
          CAST(aos.ts_event AS DATE) BETWEEN DATE('2025-01-21')
          AND DATE('2025-02-06')
        )
    LEFT JOIN 
      datalake_tracked_events.attribution_cross_channel AS acc 
        ON (off.id_firestore = acc.id_firestore)
        AND (
          acc.event_name in ('offer_submitted', 'offer_submitted_new')
        )
        AND (
          CAST(acc.ts_event AS DATE) BETWEEN DATE('2025-01-21')
          AND DATE('2025-02-06')
        )
  WHERE
    roce.id_event_type = 3
    AND roce.business_context = 'rent'
),
legacy_data_talk_to_agent AS (
  SELECT
    (
      COALESCE(agent_id, 10) || coalesce(a.tenant_id, 0) || COALESCE(a.sk_house_listing, 0) || unix_timestamp(first_message_ts)
    ) AS id_talk_to_agent,
    a.app_type,
    a.utm_medium,
    a.utm_source,
    a.utm_campaign,
    a.utm_content,
    CAST(NULL AS STRING) AS entrance_uri,
    a.utm_term,
    a.branded
  FROM
    datalake_talk_to_agent.talk_to_agent AS a
  INNER JOIN 
    datalake_ebdb_clean.house AS h 
      ON h.id = a.house_id
  WHERE
    DATE(a.first_message_ts) BETWEEN DATE('2025-01-21')
    AND DATE('2025-02-06')
),
events_with_attribution AS (
  SELECT
    INT(DATE_FORMAT(dt_event, 'yyyyMMdd')) AS id_event_date,
    id_rent_flow,
    id_sale_flow,
    id_event_type,
    event_name,
    id_booking,
    id_offer,
    NULL AS id_firestore,
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
    utm_term,
    utm_content,
    entrance_uri,
    branded,
    dt_event,
    ts_event
  FROM
    booking_attribution
  UNION ALL
  SELECT
    INT(DATE_FORMAT(dt_event, 'yyyyMMdd')) AS id_event_date,
    id_rent_flow,
    id_sale_flow,
    id_event_type,
    event_name,
    id_booking,
    id_offer,
    id_offer AS id_firestore,
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
    utm_term,
    utm_content,
    entrance_uri,
    branded,
    dt_event,
    ts_event
  FROM
    sale_offer_attribution
  UNION ALL
  SELECT
    INT(DATE_FORMAT(dt_event, 'yyyyMMdd')) AS id_event_date,
    id_rent_flow,
    id_sale_flow,
    id_event_type,
    event_name,
    id_booking,
    id_offer,
    id_firestore,
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
    utm_term,
    utm_content,
    entrance_uri,
    branded,
    dt_event,
    ts_event
  FROM
    rent_offer_attribution
  UNION ALL
  SELECT
    INT(DATE_FORMAT(ce.dt_event, 'yyyyMMdd')) AS id_event_date,
    ce.id_rent_flow,
    ce.id_sale_flow,
    ce.id_event_type,
    ce.event_name,
    ce.id_booking,
    ce.id_offer,
    NULL AS id_firestore,
    ce.id_talk_to_agent,
    ce.id_house,
    ce.id_region,
    ce.id_prospect,
    ce.id_owner,
    ce.id_agent,
    ce.business_context,
    ldtta.app_type,
    ldtta.utm_medium,
    ldtta.utm_source,
    ldtta.utm_campaign,
    ldtta.utm_term,
    ldtta.utm_content,
    ldtta.entrance_uri,
    ldtta.branded,
    ce.dt_event,
    ce.ts_event
  FROM
    conversion_events_filtered AS ce
  LEFT JOIN 
    legacy_data_talk_to_agent ldtta 
      ON ce.id_talk_to_agent = ldtta.id_talk_to_agent
  WHERE
    ce.id_event_type = 99
),
booking_info AS (
  SELECT
    b.id AS id_booking,
    b.code AS visit_code,
    CASE
      WHEN b.id_user_creation = b.id_user_sale_agent THEN 'Agent'
      WHEN b.id_user_creation = b.id_visitor THEN 'SelfService'
      WHEN b.id_user_creation = b.id_user_sale_attendence_5a THEN 'Secretaria'
      WHEN b.user_creation_email LIKE '%quintoandar.com.br' THEN 'Admin/CX'
      ELSE 'Other'
    END AS user_booking_creator,
    first_update_source,
    is_3p_demand,
    is_via_reschedule AS flg_via_reschedule,
    ts_created
  FROM
    datalake_booking.booking AS b
) -- , final AS(
SELECT
  MD5(
    CONCAT(
      e.ts_event,
      e.id_event_type,
      e.business_context,
      COALESCE(e.id_booking, -1),
      COALESCE(e.id_offer, -1),
      COALESCE(e.id_talk_to_agent, -1),
      e.id_prospect,
      e.id_house
    )
  ) AS id_demand_prospect_conversion_event,
  e.id_event_date,
  e.id_rent_flow,
  e.id_sale_flow,
  e.id_event_type,
  e.event_name,
  e.id_booking,
  e.id_offer,
  e.id_firestore,
  e.id_talk_to_agent,
  e.id_house,
  e.id_region,
  e.id_prospect,
  e.id_owner,
  e.id_agent,
  e.business_context,
  b.visit_code,
  b.user_booking_creator AS booking_creator,
  b.first_update_source AS product_origin,
  b.is_3p_demand,
  b.flg_via_reschedule,
  NULLIF(e.app_type, '') AS app_type,
  NULLIF(e.utm_medium, '') AS utm_medium,
  NULLIF(e.utm_source, '') AS utm_source,
  NULLIF(e.utm_campaign, '') AS utm_campaign,
  NULLIF(e.utm_term, '') AS utm_term,
  NULLIF(e.utm_content, '') AS utm_content,
  NULLIF(e.entrance_uri, '') AS entrance_uri,
  NULLIF(e.branded, '') AS branded,
  COALESCE(h.country_code, 'Undefined') AS country_code,
  e.dt_event,
  e.ts_event,
  YEAR(e.dt_event) AS year,
  MONTH(e.dt_event) AS month,
  DAY(e.dt_event) AS day
FROM
  events_with_attribution AS e
LEFT JOIN 
  booking_info AS b 
    ON e.id_booking = b.id_booking
  AND DATE(b.ts_created) BETWEEN DATE('2025-01-21')
  AND DATE('2025-02-06')
LEFT JOIN 
  datalake_ebdb_listing.house AS h 
    ON e.id_house = h.id
WHERE
  e.id_prospect IS NOT NULL
  AND e.id_house IS NOT NULL
  AND h.dt_creation < e.ts_event