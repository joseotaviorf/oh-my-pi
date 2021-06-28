WITH unique_buyer_prospects AS (
  SELECT
    id_buyer
  FROM
    datalake_sale_flows.sale_flow
  GROUP BY 1
),
visit_events AS (
  SELECT
    id_visitor AS id_buyer,
    COUNT(DISTINCT id) AS bookings_created,
    COUNT(DISTINCT
      CASE
        WHEN first_update_source = 'Corretores' THEN id
      END) AS bookings_created_by_agent,
    COUNT(DISTINCT
      CASE
        WHEN is_canceled = TRUE THEN id
      END) AS bookings_canceled,
    COUNT(DISTINCT
      CASE
        WHEN is_visit_completed = TRUE THEN id
      END) AS visits_completed,
    MIN(ts_created) AS ts_first_booking_created,
    MIN(
      CASE
        WHEN is_visit_completed = TRUE THEN ts_booking_utc
      END) AS ts_first_visit_completed,
    MAX(ts_created) AS ts_last_booking_created,
    MAX(
      CASE
        WHEN is_visit_completed = TRUE THEN ts_booking_utc
      END) AS ts_last_visit_completed
  FROM
    datalake_booking.booking
  WHERE
    visit_intent = 'SALE'
  GROUP BY 1
),
buyer_intention AS (
  SELECT
    id_visitor AS id_buyer,
    buyer_intention,
    ROW_NUMBER() OVER (PARTITION BY id_visitor ORDER BY ts_created) AS intention_order
  FROM
    datalake_booking.booking
  WHERE
    visit_intent = 'SALE'
    AND buyer_intention IS NOT NULL
),
offer_events AS (
  SELECT
    id_buyer,
    COUNT(DISTINCT id_offer) AS offers_submitted,
    COUNT(DISTINCT
      CASE
        WHEN dt_offer_accepted IS NOT NULL THEN id_offer
      END) AS offers_accepted,
    COUNT(DISTINCT
      CASE
        WHEN dt_offer_dismissed IS NOT NULL THEN id_offer
      END) AS offers_dismissed,
    COUNT(DISTINCT
      CASE
        WHEN dt_sale_agreement_signed IS NOT NULL THEN id_offer
      END) AS sale_agreements_signed,
    AVG(first_price_offered_by_buyer) AS avg_offer_price,
    AVG(1-(first_price_offered_by_buyer/sale_price)) AS avg_offer_discount,
    MIN(ts_offer_submitted) AS ts_first_offer_submitted,
    MIN(dt_offer_accepted) AS dt_first_offer_accepted,
    MIN(dt_sale_agreement_signed) AS dt_first_sale_agreement_signed,
    MAX(ts_offer_submitted) AS ts_last_offer_submitted,
    MAX(dt_offer_accepted) AS dt_last_offer_accepted,
    MAX(dt_sale_agreement_signed) AS dt_last_sale_agreement_signed
  FROM
    datalake_offer.sale_offer
  GROUP BY 1
),
sale_flow_events AS (
  SELECT
    sf.id_buyer,
    COUNT(DISTINCT sf.id_sale_flow) AS sale_flows,
    COUNT(DISTINCT sf.id_region) AS regions_with_sale_flows,
    COUNT(DISTINCT date_trunc('week', sf.ts_first_event)) AS weeks_with_sale_flows,
    AVG(NULLIF(h.sale_price, 0)) AS avg_sale_price,
    MIN(sf.ts_first_event) AS ts_first_sale_flow,
    MAX(sf.ts_first_event) AS ts_last_sale_flow
  FROM
    datalake_sale_flows.sale_flow sf
  JOIN
    datalake_ebdb_clean.house h
      ON h.id = sf.id_house
  GROUP BY 1
),
first_last_values AS (
  SELECT
    sf.id_buyer,
    MAX(fst.id_region) AS id_first_region,
    MAX(fst.first_event) AS first_event,
    MAX(lst.id_region) AS id_last_region
  FROM
    sale_flow_events sf
  LEFT JOIN
    datalake_sale_flows.sale_flow fst
      ON fst.ts_first_event = sf.ts_first_sale_flow
      AND fst.id_buyer = sf.id_buyer
  LEFT JOIN
    datalake_sale_flows.sale_flow lst
      ON lst.ts_first_event = sf.ts_last_sale_flow
      AND lst.id_buyer = sf.id_buyer
  GROUP BY 1
),
flag_owner AS (
  SELECT
    h.id_user AS id_buyer,
    COUNT(DISTINCT h.id) AS houses_owned,
    COUNT(DISTINCT
      CASE
        WHEN business_context = 'SALE' THEN  h.id
      END) AS listings_for_sale,
    COUNT(DISTINCT
      CASE
        WHEN business_context = 'RENT' THEN  h.id
      END) AS listings_for_rent
  FROM
    datalake_ebdb_clean.house h
  JOIN
    datalake_ebdb_listing.listing_business_context lbc
      ON lbc.id_house = h.id
  JOIN
    unique_buyer_prospects sf
      ON sf.id_buyer = h.id_user
  GROUP BY 1
),
flag_tenant AS (
  SELECT
    cp.id_user AS id_buyer,
    MAX(
      CASE
        WHEN cp.type in ('Inquilino','Morador') THEN TRUE
        ELSE FALSE
      END) AS is_tenant,
    MAX(
      CASE
        WHEN cp.type in ('Proprietario') THEN TRUE
        ELSE FALSE
      END) AS is_contract_owner,
    MAX(
      CASE
        WHEN cp.type in ('Inquilino','Morador')
          AND c.status = 'Ativo' THEN TRUE
        ELSE FALSE
      END) AS is_current_tenant
  FROM
    datalake_ebdb_clean.contract_person cp
  JOIN
    datalake_ebdb_contract.contract c
      ON c.id = cp.id_contract
  JOIN
    unique_buyer_prospects sf
      ON sf.id_buyer = cp.id_user
  GROUP BY 1
),
flag_tenant_prospect AS (
  SELECT
    sf.id_buyer,
    MAX(
      CASE
        WHEN b.visit_intent ='RENT' OR o.id_client IS NOT NULL THEN TRUE
        ELSE FALSE
      END) AS is_tenant_prospect
  FROM
    unique_buyer_prospects sf
  LEFT JOIN
    datalake_booking.booking b
      ON sf.id_buyer = b.id_visitor
  LEFT JOIN
    datalake_offer.offer o
      ON o.id_client = sf.id_buyer
  GROUP BY 1
)
SELECT
  u.id_buyer,
  fl.id_first_region,
  fl.id_last_region,
  fl.first_event,
  CASE
    WHEN GREATEST(sf.ts_last_sale_flow,v.ts_last_booking_created,v.ts_last_visit_completed,
          o.ts_last_offer_submitted,o.dt_last_offer_accepted,o.dt_last_sale_agreement_signed) = v.ts_last_booking_created
      THEN 'booking_created'
    WHEN GREATEST(sf.ts_last_sale_flow,v.ts_last_booking_created,v.ts_last_visit_completed,
          o.ts_last_offer_submitted,o.dt_last_offer_accepted,o.dt_last_sale_agreement_signed) = v.ts_last_visit_completed
      THEN 'visit_completed'
    WHEN GREATEST(sf.ts_last_sale_flow,v.ts_last_booking_created,v.ts_last_visit_completed,
          o.ts_last_offer_submitted,o.dt_last_offer_accepted,o.dt_last_sale_agreement_signed) = o.ts_last_offer_submitted
      THEN 'offer_submitted'
    WHEN GREATEST(sf.ts_last_sale_flow,v.ts_last_booking_created,v.ts_last_visit_completed,
          o.ts_last_offer_submitted,o.dt_last_offer_accepted,o.dt_last_sale_agreement_signed) = o.dt_last_offer_accepted
      THEN 'offer_accepted'
    WHEN GREATEST(sf.ts_last_sale_flow,v.ts_last_booking_created,v.ts_last_visit_completed,
          o.ts_last_offer_submitted,o.dt_last_offer_accepted,o.dt_last_sale_agreement_signed) = o.dt_last_sale_agreement_signed
      THEN 'sale_agreement_signed'
    WHEN GREATEST(v.ts_last_booking_created,o.ts_last_offer_submitted) != sf.ts_last_sale_flow
          OR fl.first_event = 'talk_to_agent'
      THEN 'talk_to_agent'
  END AS last_event,
  CASE
    WHEN COALESCE(o.dt_first_sale_agreement_signed,o.dt_first_offer_accepted,o.ts_first_offer_submitted,
                  v.ts_first_visit_completed, v.ts_first_booking_created) = o.dt_first_sale_agreement_signed
      THEN 'sale_agreement_signed'
    WHEN COALESCE(o.dt_first_sale_agreement_signed,o.dt_first_offer_accepted,o.ts_first_offer_submitted,
                  v.ts_first_visit_completed, v.ts_first_booking_created) = o.dt_first_offer_accepted
      THEN 'offer_accepted'
    WHEN COALESCE(o.dt_first_sale_agreement_signed,o.dt_first_offer_accepted,o.ts_first_offer_submitted,
                  v.ts_first_visit_completed, v.ts_first_booking_created) = o.ts_first_offer_submitted
      THEN 'offer_submitted'
    WHEN COALESCE(o.dt_first_sale_agreement_signed,o.dt_first_offer_accepted,o.ts_first_offer_submitted,
                  v.ts_first_visit_completed, v.ts_first_booking_created) = v.ts_first_visit_completed
      THEN 'visit_completed'
    WHEN COALESCE(o.dt_first_sale_agreement_signed,o.dt_first_offer_accepted,o.ts_first_offer_submitted,
                  v.ts_first_visit_completed, v.ts_first_booking_created) = v.ts_first_booking_created
      THEN 'booking_created'
    WHEN COALESCE(o.dt_first_sale_agreement_signed,o.dt_first_offer_accepted,o.ts_first_offer_submitted,
                  v.ts_first_visit_completed, v.ts_first_booking_created) IS NULL
      THEN 'talk_to_agent'
  END AS further_funnel_step,
  bi.buyer_intention AS first_buyer_intention,
  COALESCE(ft.is_tenant, FALSE) AS is_tenant,
  COALESCE(ft.is_current_tenant, FALSE) AS is_current_tenant,
  COALESCE(ft.is_contract_owner, FALSE) AS is_contract_owner,
  COALESCE(ftp.is_tenant_prospect, FALSE) AS is_tenant_prospect,
  sf.sale_flows,
  sf.regions_with_sale_flows,
  sf.weeks_with_sale_flows,
  COALESCE(v.bookings_created,0) AS bookings_created,
  COALESCE(v.bookings_created_by_agent,0) AS bookings_created_by_agent,
  COALESCE(v.bookings_canceled,0) AS bookings_canceled,
  COALESCE(v.visits_completed,0) AS visits_completed,
  COALESCE(o.offers_submitted,0) AS offers_submitted,
  COALESCE(o.offers_accepted,0) AS offers_accepted,
  COALESCE(o.offers_dismissed,0) AS offers_dismissed,
  COALESCE(o.sale_agreements_signed,0) AS sale_agreements_signed,
  sf.avg_sale_price,
  o.avg_offer_price,
  o.avg_offer_discount,
  COALESCE(fo.houses_owned,0) AS houses_owned,
  COALESCE(fo.listings_for_sale,0) AS listings_for_sale,
  COALESCE(fo.listings_for_rent,0) AS listings_for_rent,
  DATEDIFF(v.ts_first_booking_created,sf.ts_first_sale_flow) AS days_first_sale_flow_to_first_booking_created,
  DATEDIFF(v.ts_first_visit_completed,sf.ts_first_sale_flow) AS days_first_sale_flow_to_first_visit_completed,
  DATEDIFF(o.ts_first_offer_submitted,sf.ts_first_sale_flow) AS days_first_sale_flow_to_first_offer_submitted,
  DATEDIFF(o.dt_first_offer_accepted,sf.ts_first_sale_flow) AS days_first_sale_flow_to_first_offer_accepted,
  DATEDIFF(o.dt_first_sale_agreement_signed,sf.ts_first_sale_flow) AS days_first_sale_flow_to_first_sale_agreement_signed,
  DATEDIFF(v.ts_first_visit_completed,v.ts_first_booking_created) AS days_first_booking_created_to_first_visit_completed,
  DATEDIFF(o.ts_first_offer_submitted,v.ts_first_booking_created) AS days_first_booking_created_to_first_offer_submitted,
  DATEDIFF(o.dt_first_offer_accepted,v.ts_first_booking_created) AS days_first_booking_created_to_first_offer_accepted,
  DATEDIFF(o.dt_first_sale_agreement_signed,v.ts_first_booking_created) AS days_first_booking_created_to_first_sale_agreement_signed,
  DATEDIFF(o.ts_first_offer_submitted,v.ts_first_visit_completed) AS days_first_visit_completed_to_first_offer_submitted,
  DATEDIFF(o.dt_first_offer_accepted,v.ts_first_visit_completed) AS days_first_visit_completed_to_first_offer_accepted,
  DATEDIFF(o.dt_first_sale_agreement_signed,v.ts_first_visit_completed) AS days_first_visit_completed_to_first_sale_agreement_signed,
  DATEDIFF(o.dt_first_offer_accepted,o.ts_first_offer_submitted) AS days_first_offer_submitted_to_first_offer_accepted,
  DATEDIFF(o.dt_first_sale_agreement_signed,o.ts_first_offer_submitted) AS days_first_offer_submitted_to_first_sale_agreement_signed,
  DATEDIFF(o.dt_first_sale_agreement_signed,o.dt_first_offer_accepted) AS days_first_offer_accepted_to_first_sale_agreement_signed,
  CASE
    WHEN COALESCE(sf.sale_flows,0) < 2 THEN NULL
    ELSE DATEDIFF(sf.ts_last_sale_flow,sf.ts_first_sale_flow)
  END AS days_first_sale_flow_to_last_sale_flow,
  DATEDIFF(v.ts_last_booking_created,sf.ts_first_sale_flow) AS days_first_sale_flow_to_last_booking_created,
  DATEDIFF(v.ts_last_visit_completed,sf.ts_first_sale_flow) AS days_first_sale_flow_to_last_visit_completed,
  DATEDIFF(o.ts_last_offer_submitted,sf.ts_first_sale_flow) AS days_first_sale_flow_to_last_offer_submitted,
  DATEDIFF(o.dt_last_offer_accepted,sf.ts_first_sale_flow) AS days_first_sale_flow_to_last_offer_accepted,
  DATEDIFF(o.dt_last_sale_agreement_signed,sf.ts_first_sale_flow) AS days_first_sale_flow_to_last_sale_agreement_signed,
  DATEDIFF(GREATEST(sf.ts_last_sale_flow,v.ts_last_booking_created,v.ts_last_visit_completed,
          o.ts_last_offer_submitted,o.dt_last_offer_accepted,o.dt_last_sale_agreement_signed),sf.ts_first_sale_flow) AS days_first_sale_flow_to_last_event,
  CASE
    WHEN COALESCE(v.bookings_created,0) < 2 THEN NULL
    ELSE DATEDIFF(v.ts_last_booking_created,v.ts_first_booking_created)
  END AS days_first_booking_created_to_last_booking_created,
  DATEDIFF(v.ts_last_visit_completed,v.ts_first_booking_created) AS days_first_booking_created_to_last_visit_completed,
  DATEDIFF(o.ts_last_offer_submitted,v.ts_first_booking_created) AS days_first_booking_created_to_last_offer_submitted,
  DATEDIFF(o.dt_last_offer_accepted,v.ts_first_booking_created) AS days_first_booking_created_to_last_offer_accepted,
  DATEDIFF(o.dt_last_sale_agreement_signed,v.ts_first_booking_created) AS days_first_booking_created_to_last_sale_agreement_signed,
  CASE
    WHEN COALESCE(v.visits_completed,0) < 2 THEN NULL
    ELSE DATEDIFF(v.ts_last_visit_completed,v.ts_first_visit_completed)
  END AS days_first_visit_completed_to_last_visit_completed,
  DATEDIFF(o.ts_last_offer_submitted,v.ts_first_visit_completed) AS days_first_visit_completed_to_last_offer_submitted,
  DATEDIFF(o.dt_last_offer_accepted,v.ts_first_visit_completed) AS days_first_visit_completed_to_last_offer_accepted,
  DATEDIFF(o.dt_last_sale_agreement_signed,v.ts_first_visit_completed) AS days_first_visit_completed_to_last_sale_agreement_signed,
  CASE
    WHEN COALESCE(o.offers_submitted,0) < 2 THEN NULL
    ELSE DATEDIFF(o.ts_last_offer_submitted,o.ts_first_offer_submitted)
  END AS days_first_offer_submitted_to_last_offer_submitted,
  DATEDIFF(o.dt_last_offer_accepted,o.ts_first_offer_submitted) AS days_first_offer_submitted_to_last_offer_accepted,
  DATEDIFF(o.dt_last_sale_agreement_signed,o.ts_first_offer_submitted) AS days_first_offer_submitted_to_last_sale_agreement_signed,
  CASE
    WHEN COALESCE(o.offers_accepted,0) < 2 THEN NULL
    ELSE DATEDIFF(o.dt_last_offer_accepted,o.dt_first_offer_accepted)
  END AS days_first_offer_accepted_to_last_offer_accepted,
  DATEDIFF(o.dt_last_sale_agreement_signed,o.dt_first_offer_accepted) AS days_first_offer_accepted_to_last_sale_agreement_signed,
  CASE
    WHEN COALESCE(o.sale_agreements_signed,0) < 2  THEN NULL
    ELSE DATEDIFF(o.dt_last_sale_agreement_signed,o.dt_first_sale_agreement_signed)
  END AS days_first_sale_agreement_signed_to_last_sale_agreement_signed,
  sf.ts_first_sale_flow,
  v.ts_first_booking_created,
  v.ts_first_visit_completed,
  o.ts_first_offer_submitted,
  o.dt_first_offer_accepted,
  o.dt_first_sale_agreement_signed,
  sf.ts_last_sale_flow,
  v.ts_last_booking_created,
  v.ts_last_visit_completed,
  o.ts_last_offer_submitted,
  o.dt_last_offer_accepted,
  o.dt_last_sale_agreement_signed,
  GREATEST(sf.ts_last_sale_flow,v.ts_last_booking_created,v.ts_last_visit_completed,
          o.ts_last_offer_submitted,o.dt_last_offer_accepted,o.dt_last_sale_agreement_signed) AS ts_last_event
FROM
  unique_buyer_prospects AS u
LEFT JOIN
  visit_events v
    ON u.id_buyer = v.id_buyer
LEFT JOIN
  buyer_intention bi
    ON u.id_buyer = bi.id_buyer
    AND bi.intention_order = 1
LEFT JOIN
  offer_events o
    ON u.id_buyer = o.id_buyer
LEFT JOIN
  sale_flow_events sf
    ON u.id_buyer = sf.id_buyer
LEFT JOIN
  first_last_values fl
    ON u.id_buyer = fl.id_buyer
LEFT JOIN
  flag_owner fo
    ON u.id_buyer = fo.id_buyer
LEFT JOIN
  flag_tenant ft
    ON u.id_buyer = ft.id_buyer
LEFT JOIN
  flag_tenant_prospect ftp
    ON u.id_buyer = ftp.id_buyer
