WITH taxonomy_demand AS (
  WITH taxonomy_min_ids AS (
    SELECT
      MIN(id) AS id
    FROM
      datalake_gsheets_clean.taxonomy_demand
    WHERE
      first_update_source = 'Inquilinos'
      AND flg_via_reschedule = 0
    GROUP BY
      LOWER(app_type),
      LOWER(utm_source),
      LOWER(utm_medium),
      LOWER(branded),
      LOWER(first_update_source),
      flg_via_reschedule
  )
  SELECT
    CAST(td.id AS BIGINT) AS id,
    td.app_type,
    td.utm_source,
    td.utm_medium,
    td.branded,
    td.category AS mkt_category,
    td.flow AS mkt_flow,
    td.completion AS mkt_completion,
    td.channel AS mkt_channel,
    td.medium AS mkt_medium,
    td.origin AS mkt_origin,
    td.source AS mkt_source,
    td.platform AS mkt_platform
  FROM
    datalake_gsheets_clean.taxonomy_demand AS td
  JOIN
    taxonomy_min_ids AS td_min
      ON td.id = td_min.id
),
events_taxonomy AS (
    /*
    Attribution Rules, enriched with the new attribution and the old one.
    The new one starts on H2/2021.
    Using CASE WHEN instead of COALESCE to don't create strange combinations.
    */
-- UTM's from booking events
  SELECT
    CONCAT(b.id_visitor, '_', b.id_house) AS id_sale_flow,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_source
      ELSE av.utm_source
    END AS utm_source,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_medium
      ELSE av.utm_medium
    END AS utm_medium,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_campaign
      ELSE av.utm_campaign
    END AS utm_campaign,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_branded
      ELSE av.branded
    END AS branded,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_app_type
      ELSE av.app_type
    END AS app_type,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_origin
      ELSE 'old_attribution'
    END AS final_attribution_origin,
    CAST(av.ts_event AS TIMESTAMP) AS ts_event
  FROM
    datalake_amplitude_visit.amplitude_visit AS av
  LEFT JOIN
    datalake_tracked_events.attribution_cross_channel AS acc
      ON av.id_visit = acc.visit_code
  JOIN
    datalake_ebdb_clean.visit AS v
      ON v.code = av.id_visit
  JOIN
    datalake_booking.booking AS b
      ON b.id_visit = v.id
  WHERE
    b.visit_intent = 'SALE'
    AND b.type = 'Visita'
  UNION
-- UTM's from offer events
  SELECT
    CONCAT(so.id_user, '_', so.id_house) AS id_sale_flow,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_source
      ELSE so.utm_source
    END AS utm_source,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_medium
      ELSE so.utm_medium
    END AS utm_medium,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_campaign
      ELSE so.utm_campaign
    END AS utm_campaign,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_branded
      ELSE so.branded
    END AS branded,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_app_type
      ELSE so.app_type
    END AS app_type,
    CASE
      WHEN acc.visit_code IS NOT NULL THEN acc.final_attribution_origin
      ELSE 'old_attribution'
    END AS final_attribution_origin,
    CAST(so.ts_event AS TIMESTAMP) AS ts_event
  FROM
    datalake_amplitude_offer.sale_offer_raw_events AS so
  LEFT JOIN
    datalake_tracked_events.attribution_cross_channel AS acc
      ON acc.event_name = 'sale_offer_form_accepted'
      AND so.id_user = acc.id_user
      AND so.id_house = acc.id_house
  UNION
-- UTM's from talk_to_agent events
  SELECT
    CONCAT(tta.id_user, '_', tta.id_house) AS id_sale_flow,
    tta.utm_source,
    tta.utm_medium,
    tta.utm_campaign,
    tta.branded,
    tta.app_type,
    'old_attribution' AS final_attribution_origin,
    CAST(ts_event AS TIMESTAMP) AS ts_event
  FROM
    datalake_talk_to_agent.talk_to_agent_events AS tta
  JOIN
    datalake_ebdb_listing.listing_business_context AS lbc
      ON tta.id_house = lbc.id_house
  WHERE
    CAST(tta.ts_event AS DATE) > DATE('2020-03-01') -- month_start of tta event
    AND tta.business_context = 'SALE'
    AND lbc.business_context = 'SALE'
    AND tta.id_house IS NOT NULL
    AND tta.id_user IS NOT NULL
),
sale_flow_taxonomy AS (
  SELECT
    et.*,
    et.branded ='Branded' AS is_branded,
    td.mkt_category,
    td.mkt_flow,
    td.mkt_completion,
    td.mkt_origin,
    td.mkt_channel,
    td.mkt_medium,
    td.mkt_source,
    td.mkt_platform,
    ROW_NUMBER() OVER (PARTITION BY et.id_sale_flow ORDER BY et.ts_event) AS rn_sale_flow
  FROM
    events_taxonomy AS et
  LEFT JOIN
    taxonomy_demand AS td
      ON LOWER(COALESCE(td.app_type,'')) = LOWER(COALESCE(et.app_type,''))
      AND LOWER(COALESCE(td.utm_source,'')) = LOWER(COALESCE(et.utm_source,''))
      AND LOWER(COALESCE(td.utm_medium,'')) = LOWER(COALESCE(et.utm_medium,''))
      AND LOWER(COALESCE(td.branded,'')) = LOWER(COALESCE(et.branded,''))
)
SELECT
  sf.id_sale_flow AS sk_sale_flow,
  sf.id_buyer AS sk_buyer,
  sf.id_house AS sk_house,
  sf.id_seller AS sk_seller,
  COALESCE(sf.id_region,-1) AS sk_region,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.ts_first_listing,1, 10),'-','') AS BIGINT), -1) AS sk_first_listing_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.ts_first_event,1, 10),'-','') AS BIGINT), -1) AS sk_first_event_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.ts_first_tta_message_sent,1, 10),'-','') AS BIGINT), -1) AS sk_first_tta_message_sent_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.ts_first_booking_created,1, 10),'-','') AS BIGINT), -1) AS sk_first_booking_created_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.ts_first_visit_completed,1, 10),'-','') AS BIGINT), -1) AS sk_first_visit_completed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.ts_first_offer_submitted,1, 10),'-','') AS BIGINT), -1) AS sk_first_offer_submitted_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.dt_first_offer_accepted,1, 10),'-','') AS BIGINT), -1) AS sk_first_offer_accepted_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.dt_first_offer_dismissed,1, 10),'-','') AS BIGINT), -1) AS sk_first_offer_dismissed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.dt_sale_agreement_created,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_created_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.dt_sale_agreement_signed,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_signed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.dt_sale_agreement_cancelled,1, 10),'-','') AS BIGINT), -1) AS sk_sale_agreement_cancelled_date,
  COALESCE(CAST(REPLACE(SUBSTRING(sf.dt_house_registry_ended,1, 10),'-','') AS BIGINT), -1) AS sk_house_registry_ended_date,
  sf.first_event,
  sf.higher_intent_before_offer,
  sf.higher_intent_after_offer,
  sf.rank_buyer_sale_flow,
  sf.rank_house_sale_flow,
  sf.is_buyer_first_sale_flow,
  sf.is_house_first_sale_flow,
  sf.flow_type,
  sf.max_discount_proposed,
  sf.bookings,
  sf.visits_completed,
  sf.offers_submitted,
  sf.tta_messages_sent,
  sf.days_first_publication_to_first_event,
  sf.days_first_publication_to_first_booking_created,
  sf.days_first_publication_to_first_visit_completed,
  sf.days_first_publication_to_first_offer_submitted,
  sf.days_first_publication_to_first_offer_accepted,
  sf.days_first_publication_to_sale_agreement_signed,
  sf.days_first_publication_to_house_registry_ended,
  sf.days_first_event_to_first_visit_completed,
  sf.days_first_event_to_first_offer_submitted,
  sf.days_first_event_to_first_offer_accepted,
  sf.days_first_event_to_sale_agreement_signed,
  sf.days_first_event_to_house_registry_ended,
  sf.days_first_booking_created_to_first_visit_completed,
  sf.days_first_booking_created_to_first_offer_submitted,
  sf.days_first_booking_created_to_first_offer_accepted,
  sf.days_first_booking_created_to_sale_agreement_signed,
  sf.days_first_booking_created_to_house_registry_ended,
  sf.days_first_visit_completed_to_first_offer_submitted,
  sf.days_first_visit_completed_to_first_offer_accepted,
  sf.days_first_visit_completed_to_sale_agreement_signed,
  sf.days_first_visit_completed_to_house_registry_ended,
  sf.days_first_offer_submitted_to_first_offer_accepted,
  sf.days_first_offer_submitted_to_sale_agreement_signed,
  sf.days_first_offer_accepted_to_sale_agreement_signed,
  sf.days_first_offer_submitted_to_house_registry_ended,
  tx.final_attribution_origin,
  COALESCE(tx.app_type, '') AS app_type,
  COALESCE(tx.utm_source, '') AS utm_source,
  COALESCE(tx.utm_medium, '') AS utm_medium,
  COALESCE(tx.utm_campaign, '') AS utm_campaign,
  COALESCE(tx.is_branded, FALSE) AS is_branded,
  COALESCE(tx.mkt_category,'Not Mapped') AS mkt_category,
  COALESCE(tx.mkt_flow,'Not Mapped') AS mkt_flow,
  COALESCE(tx.mkt_completion,'Not Mapped') AS mkt_completion,
  COALESCE(tx.mkt_origin,'Not Mapped') AS mkt_origin,
  COALESCE(tx.mkt_channel,'Not Mapped') AS mkt_channel,
  COALESCE(tx.mkt_medium,'Not Mapped') AS mkt_medium,
  COALESCE(tx.mkt_source,'Not Mapped') AS mkt_source,
  COALESCE(tx.mkt_platform,'Not Mapped') AS mkt_platform,
  sf.ts_first_listing,
  sf.ts_first_event,
  sf.ts_first_tta_message_sent,
  sf.ts_first_booking_created,
  sf.ts_first_visit_completed,
  sf.ts_first_offer_submitted,
  sf.dt_first_offer_accepted AS ts_first_offer_accepted,
  sf.dt_first_offer_dismissed AS ts_first_offer_dismissed,
  CAST(sf.dt_sale_agreement_created AS TIMESTAMP) AS ts_sale_agreement_created,
  sf.dt_sale_agreement_signed AS ts_sale_agreement_signed,
  CAST(sf.dt_sale_agreement_cancelled AS TIMESTAMP) AS ts_sale_agreement_cancelled,
  CAST(sf.dt_house_registry_ended AS TIMESTAMP) AS ts_house_registry_ended,
  NOW() AS ts_load
FROM
  datalake_sale_flows.sale_flow AS sf
LEFT JOIN
  sale_flow_taxonomy AS tx
    ON sf.id_sale_flow = tx.id_sale_flow
    AND tx.rn_sale_flow = 1
-- This filter was needed because the datalake_gsheets.sale_hub_offer table has no information about id_sale_flow.
-- TODO: The idea is to transform the datalake_gsheets.sale_hub_offer into a static table in the future to fill in this information and remove this filter.
WHERE
  sf.id_sale_flow IS NOT NULL
