WITH offer_after_booking AS (
  SELECT
    id_booking,
    id_offer,
    hours_booking_to_offer,
    hours_visit_to_offer
  FROM
    datalake_offer.sale_offer
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY id_booking ORDER BY ts_offer_submitted) = 1 
),
buyer_review AS (
  SELECT 
    id_reviewed,
    id_reviewer,
    dt_creation
  FROM 
    datalake_insider_clean.review
  WHERE 
    type = 'tenant_visit'
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY id_reviewed, id_reviewer ORDER BY dt_creation ASC) = 1 
)
SELECT
  COALESCE(b.id, -1) AS sk_booking,
  COALESCE(b.id_sale_flow, -1) AS sk_sale_flow,
  COALESCE(b.id_house, -1) AS sk_house,
  COALESCE(h.id_region, -1) AS sk_region,
  COALESCE(svh.id_business_unit, -1) AS sk_business_unit,
  COALESCE(cs_supply.sk_company, -1) AS sk_company_supply,
  COALESCE(cs_demand.sk_company, -1) AS sk_company_demand,
  COALESCE(b.id_agent, -1) AS sk_agent,
  COALESCE(ua.id, -1) AS sk_user_agent,
  COALESCE(svh.id_user_en, -1) AS sk_user_en,
  COALESCE(b.id_sale_fixed_agent, -1) AS sk_fixed_agent,
  COALESCE(b.id_visitor, -1) AS sk_buyer,
  COALESCE(h.id_user, -1) AS sk_seller,
  COALESCE(b.id_user_creation, -1) AS sk_user_creation,
  COALESCE(b.id_user_cancelation, -1) AS sk_user_cancelation,
  COALESCE(b.id_visit, -1) AS sk_visit,
  b.code AS sk_visit_code,
  COALESCE(so.id_offer, -1) AS sk_offer,
  COALESCE(ar.id, -1) AS sk_agent_booking_review,
  COALESCE(b.id, -1) AS sk_buyer_booking_review,
  COALESCE(BIGINT(DATE_FORMAT(b.ts_created, 'yyyyMMdd')), -1) AS sk_booking_created_date,
  COALESCE(BIGINT(DATE_FORMAT(b.ts_booking_utc, 'yyyyMMdd')), -1) AS sk_visit_date,
  COALESCE(BIGINT(DATE_FORMAT(b.ts_first_canceled, 'yyyyMMdd')), -1) AS sk_visit_canceled_date,
  IF(b.is_visit_completed, BIGINT(DATE_FORMAT(b.ts_booking_utc, 'yyyyMMdd')), -1) AS sk_visit_completed_date,
  COALESCE(BIGINT(DATE_FORMAT(b.ts_visit_fup, 'yyyyMMdd')), -1) AS sk_visit_follow_up_date,
  COALESCE(BIGINT(DATE_FORMAT(ar.ts_created, 'yyyyMMdd')), -1) AS sk_agent_review_rating_date,
  COALESCE(BIGINT(DATE_FORMAT(br.dt_creation, 'yyyyMMdd')), -1) AS sk_buyer_review_rating_date,
  b.hub_agent_region AS hub_agent_region,
  COALESCE(b.is_hub_flow,FALSE) AS is_hub_flow,
  COALESCE(b.is_house_rented,FALSE) AS is_house_rented,
  COALESCE(b.is_virtual_visit,FALSE) AS is_virtual_visit,
  b.days_visit_cancelled_to_visit,
  b.days_visit_booked_to_visit,
  b.days_visit_booked_to_visit_cancelled,
  b.days_visit_booked_to_visit_completed,
  so.hours_booking_to_offer,
  so.hours_visit_to_offer,
  b.ts_created AS ts_booking_created,
  b.ts_booking_utc AS ts_visit,
  b.ts_first_canceled AS ts_visit_canceled,
  IF(b.is_visit_completed, b.ts_booking_utc, NULL) AS ts_visit_completed,
  b.ts_visit_fup AS ts_visit_follow_up,
  ar.ts_created AS ts_agent_review_rating,
  br.dt_creation AS ts_buyer_review_rating,
  NOW() AS ts_load
FROM
  datalake_booking.booking AS b
JOIN
  datalake_ebdb_clean.house AS h
    ON h.id = b.id_house
LEFT JOIN
  offer_after_booking AS so
    ON b.id = so.id_booking
LEFT JOIN
  datalake_sale_visit_hubs.sale_visit_hubs AS svh
    ON svh.id_booking = b.id
LEFT JOIN
  datalake_ebdb_clean.real_estate_agent_rating AS ar
    ON ar.id = b.id_real_estate_agent_rating
LEFT JOIN
  buyer_review AS br
    ON b.code = br.id_reviewed
    AND b.id_visitor = br.id_reviewer
LEFT JOIN
  datalake_ebdb_clean.user AS ua
    ON ua.id_agent = b.id_agent
LEFT JOIN
  datalake_rede_company.company_sks AS cs_demand
    ON (b.id_company_demand IS NOT NULL
    AND b.id_company_demand = cs_demand.id_hubspot)
    OR (b.id_company_demand IS NULL
    AND b.partner_3p_demand = cs_demand.extracted_3p_tag)
LEFT JOIN
  datalake_rede_company.company_sks AS cs_supply
    ON (b.id_company_supply IS NOT NULL
    AND b.id_company_supply = cs_supply.id_hubspot)
    OR (b.id_company_supply IS NULL
    AND b.partner_3p_supply = cs_supply.extracted_3p_tag)
WHERE
  b.visit_intent = 'SALE'
