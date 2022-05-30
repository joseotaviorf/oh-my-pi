WITH lead_ AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (fhlf.mkt_origin != 'B2B' 
        OR fhlf.sk_partner = -1) THEN 'B2C' 
      WHEN fhlf.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhlf.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    COUNT(fhlf.sk_lead_date) AS leads,
    NULL::BIGINT AS prospects, -- this count is done on the prospect date because not all listings come from a lead, and maybe one lead brings multiple house listings
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_house_listing_flows AS fhlf
      ON dd.sk_date = fhlf.sk_lead_date
      AND fhlf.sk_lead_date > 0
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON dr.sk_region = fhlf.sk_region
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhlf.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP() 
  GROUP BY 1, 2, 3, 4
),
prospect AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (fhlf.mkt_origin != 'B2B' 
        OR fhlf.sk_partner = -1) THEN 'B2C' 
      WHEN fhlf.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhlf.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    COUNT(fhlf.sk_prospect_date) AS prospects, -- this count is done on the prospect date because not all listings come from a lead, and maybe one lead brings multiple house listings
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_house_listing_flows AS fhlf
      ON dd.sk_date = fhlf.sk_prospect_date
      AND fhlf.sk_prospect_date > 0
  LEFT JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = fhlf.sk_region
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhlf.sk_partner 
  WHERE
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP() 
  GROUP BY 1, 2, 3, 4),
qualified AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (fhlf.mkt_origin != 'B2B' 
        OR fhlf.sk_partner = -1) THEN 'B2C' 
      WHEN fhlf.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhlf.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    COUNT(fhlf.sk_qualified_date) AS qualifieds, -- this count is done on the qualified date because not all listings come from a lead, and maybe one lead brings multiple house listings
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_house_listing_flows AS fhlf
      ON dd.sk_date = fhlf.sk_qualified_date
      AND fhlf.sk_qualified_date > 0
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON dr.sk_region = fhlf.sk_region
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhlf.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP() 
  GROUP BY 1, 2, 3, 4
),
opportunity AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (fhlf.mkt_origin != 'B2B' 
        OR fhlf.sk_partner = -1) THEN 'B2C' 
      WHEN fhlf.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhlf.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    COUNT(DISTINCT fhlf.sk_house_listing) AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_house_listing_flows AS fhlf
      ON dd.sk_date = fhlf.sk_opportunity_date
      AND fhlf.sk_opportunity_date > 0
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON dr.sk_region = fhlf.sk_region
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhlf.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP() 
  GROUP BY 1, 2, 3, 4
),
listing AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE
      WHEN (fhlf.mkt_origin != 'B2B' 
        OR fhlf.sk_partner = -1) THEN 'B2C' 
      WHEN fhlf.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhlf.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    COUNT(fhlf.sk_first_listing_date) AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN
    dw_public.fact_house_listing_flows AS fhlf
      ON dd.sk_date = fhlf.sk_first_listing_date
      AND fhlf.sk_first_listing_date > 0
  LEFT JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = fhlf.sk_region
  LEFT JOIN
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhlf.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP() 
  GROUP BY 1, 2, 3, 4
),
messages_sent AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    COUNT(DISTINCT (tta.agent_id || tta.tenant_id || tta.sk_house_listing)) AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_datamarts_cross.talk_to_agent AS tta
      ON date(tta.first_message_ts) = dd.date
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON tta.sk_house_listing = rf.sk_house_listing
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
agent_supports AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    COUNT(DISTINCT (tta.agent_id || tta.tenant_id || tta.sk_house_listing)) AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN
    dw_datamarts_cross.talk_to_agent AS tta
      ON DATE(tta.first_attendance_ts) = dd.date
  JOIN
    dw_public.fact_listing_rent_flows AS rf
      ON tta.sk_house_listing = rf.sk_house_listing
  JOIN
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()   
  GROUP BY 1, 2, 3, 4
),
visits_booked AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT as leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    COUNT(DISTINCT rf.sk_booking) AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_booking_created_date
      AND rf.sk_booking_created_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
visits_completed AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT as leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    COUNT(DISTINCT rf.sk_booking) AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_visit_date
      AND rf.sk_visit_date > 0 
      AND rf.flg_visit_completed = 1
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
offer_submitted AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    COUNT(DISTINCT rf.sk_offer) AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_offer_submitted_date
      AND rf.sk_offer_submitted_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
offer_approved AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    COUNT(DISTINCT rf.sk_offer) AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_offer_approved_date
      AND rf.sk_offer_approved_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
credit_evaluation_init AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    COUNT(DISTINCT rf.sk_offer) AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_first_credit_evaluation_init
      AND rf.sk_first_credit_evaluation_init > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
credit_evaluation_positive AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    COUNT(DISTINCT rf.sk_offer) AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_last_credit_evaluation_positive
      AND rf.sk_last_credit_evaluation_positive > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
doc_sent AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE WHEN (dhl.is_b2b != true OR fhl.sk_partner = -1) THEN 'B2C' 
        WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
        WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
        ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    COUNT(DISTINCT rf.sk_offer) AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_tenant_first_doc_sent_date
      AND rf.sk_tenant_first_doc_sent_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
doc_approved AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    COUNT(DISTINCT rf.sk_offer) AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_last_doc_analysis_approved
      AND rf.sk_last_doc_analysis_approved > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
credit_approved AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    COUNT(DISTINCT rf.sk_offer) AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_credit_analysis_approved_date
      AND rf.sk_credit_analysis_approved_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
contract_created AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE 
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    COUNT(DISTINCT rf.sk_contract) AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_contract_created_date
      AND rf.sk_contract_created_date > 0
  JOIN
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
contract_signed AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE
      WHEN (dhl.is_b2b != true 
        OR fhl.sk_partner = -1) THEN 'B2C' 
      WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
      WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
      ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    COUNT(DISTINCT rf.sk_contract) AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_contract_signed_date
      AND rf.sk_contract_signed_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
),
contract_ended AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    CASE WHEN (dhl.is_b2b != true OR fhl.sk_partner = -1) THEN 'B2C' 
        WHEN fhl.sk_partner IN (6,7,8) THEN 'Thaís Imobiliária' 
        WHEN fhl.sk_partner > 50 THEN 'B2B - AA'
        ELSE dp.trade_name 
    END AS partner,
    NULL::BIGINT AS leads,
    NULL::BIGINT AS prospects,
    NULL::BIGINT AS qualifieds,
    NULL::BIGINT AS opportunities,
    NULL::BIGINT AS first_listings,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS visits_completed,
    NULL::BIGINT AS offer_submitted,
    NULL::BIGINT AS offer_approved,
    NULL::BIGINT AS credit_evaluation_init,
    NULL::BIGINT AS credit_evaluation_positive,
    NULL::BIGINT AS doc_sent,
    NULL::BIGINT AS doc_approved,
    NULL::BIGINT AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    COUNT(DISTINCT rf.sk_contract) AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    dw_public.fact_listing_rent_flows AS rf
      ON dd.sk_date = rf.sk_contract_annulment_date
      AND rf.sk_contract_signed_date > 0 
      AND rf.sk_contract_annulment_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  LEFT JOIN 
    dw_public.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing 
  LEFT JOIN 
    dw_public.dim_partner AS dp 
      ON dp.sk_partner = fhl.sk_partner 
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP()  
  GROUP BY 1, 2, 3, 4
)
,
union_all AS (
  SELECT * FROM lead_
  UNION ALL
  SELECT * FROM prospect
  UNION ALL
  SELECT * FROM qualified
  UNION ALL
  SELECT * FROM opportunity
  UNION ALL
  SELECT * FROM listing
  UNION ALL
  SELECT * FROM messages_sent
  UNION ALL
  SELECT * FROM agent_supports
  UNION ALL
  SELECT * FROM visits_booked
  UNION ALL
  SELECT * FROM visits_completed
  UNION ALL
  SELECT * FROM offer_submitted
  UNION ALL
  SELECT * FROM offer_approved
  UNION ALL
  SELECT * FROM credit_evaluation_init
  UNION ALL
  SELECT * FROM credit_evaluation_positive
  UNION ALL
  SELECT * FROM doc_sent
  UNION ALL
  SELECT * FROM doc_approved
  UNION ALL
  SELECT * FROM credit_approved
  UNION ALL
  SELECT * FROM contract_created
  UNION ALL
  SELECT * FROM contract_signed
  UNION ALL
  SELECT * FROM contract_ended
), 
union_all_date AS (
  SELECT
    dd.date,
    ua.city_group,
    ua.partner,
    ua.leads,
    ua.prospects,
    ua.qualifieds,
    ua.opportunities,
    ua.first_listings,
    ua.messages_sent_tta,
    ua.registered_agent_supports,
    ua.visits_booked,
    ua.visits_completed,
    ua.offer_submitted,
    ua.offer_approved,
    ua.credit_evaluation_init,
    ua.credit_evaluation_positive,
    ua.doc_sent,
    ua.doc_approved,
    ua.credit_approved,
    ua.contract_created,
    ua.contract_signed,
    ua.contract_ended
  FROM 
    union_all AS ua
  RIGHT JOIN 
    dw_public.dim_date AS dd
      ON ua.sk_date = dd.sk_date
  WHERE
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '1 year' AND CURRENT_TIMESTAMP() 
),
agg_all AS (
  SELECT
    date,
    city_group,
    partner,
    SUM(leads) AS leads,
    SUM(prospects) AS prospects,
    SUM(qualifieds) AS qualifieds,
    SUM(opportunities) AS opportunities,
    SUM(first_listings) AS first_listings,
    SUM(messages_sent_tta) AS messages_sent_tta,
    SUM(registered_agent_supports) AS registered_agent_supports,
    SUM(visits_booked) AS visits_booked,
    SUM(visits_completed) AS visits_completed,
    SUM(offer_submitted) AS offer_submitted,
    SUM(offer_approved) AS offer_approved,
    SUM(credit_evaluation_init) AS credit_evaluation_init,
    SUM(credit_evaluation_positive) AS credit_evaluation_positive,
    SUM(doc_sent) AS doc_sent,
    SUM(doc_approved) AS doc_approved,
    SUM(credit_approved) AS credit_approved,
    SUM(contract_created) AS contract_created,
    SUM(contract_signed) AS contract_signed,
    SUM(contract_ended) AS contract_ended
  FROM 
    union_all
  GROUP BY 
    date, 
    city_group, 
    partner
)
SELECT
  *,
  CURRENT_TIMESTAMP AS ts_load
FROM
  agg_all
