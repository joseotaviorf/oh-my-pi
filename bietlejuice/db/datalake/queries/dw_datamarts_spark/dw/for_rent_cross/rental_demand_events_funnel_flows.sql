WITH rent_flows_adap AS (
-- adpating rent_flows output so we can add tta events and the category of each flow
  WITH tta_complete AS (
    SELECT
      sk_house_listing,
      tenant_id AS sk_client,
      agent_id,
      region_code,
      DATE(first_message_ts) AS first_message_date,
      DATE(first_attendance_ts) AS first_attendance_date
    FROM 
      dw_datamarts_cross.talk_to_agent
  )
  SELECT
    rf.sk_rent_flow,
    rf.sk_house_listing,
    rf.sk_client,
    rf.sk_region,
    tta_c.region_code,
    rf.sk_visit_date,
    rf.flg_visit_completed,
    rf.sk_proposal,
    rf.sk_contract_annulment_date,
    rf.sk_booking,
    rf.sk_booking_created_date,
    rf.sk_offer,
    rf.sk_offer_submitted_date,
    rf.sk_offer_approved_date,
    rf.sk_first_credit_evaluation_init,
    rf.sk_first_credit_evaluation_positive,
    rf.sk_tenant_first_doc_sent_date,
    rf.sk_last_doc_analysis_approved,
    rf.sk_credit_analysis_init_date,
    rf.sk_credit_analysis_end_date,
    rf.sk_credit_analysis_approved_date,
    rf.sk_contract,
    rf.sk_contract_created_date,
    rf.sk_contract_signed_date,
    fdf.funnel_flow,
    fdf.funnel_first_touchpoint,
    fdf.had_flow_visit,
    fdf.had_flow_direct,
    fdf.had_flow_tta,
    fdf.flow_type,
    tta_c.first_message_date,
    tta_c.first_attendance_date,
    tta_c.sk_house_listing || tta_c.sk_client || tta_c.agent_id as tta_id
  FROM 
    dw_public.fact_listing_rent_flows AS rf
  LEFT JOIN 
    dw_datamarts.funnel_demand_flows AS fdf
      ON rf.sk_rent_flow = fdf.sk_rent_flow
  FULL OUTER JOIN 
    tta_complete AS tta_c
      ON rf.sk_house_listing = tta_c.sk_house_listing
      AND rf.sk_client = tta_c.sk_client
),
messages_sent AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    'Other' AS demand_channel,
    COUNT(DISTINCT rf.tta_id) AS messages_sent_tta,
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
    rent_flows_adap AS rf
      ON DATE(rf.first_message_date) = dd.date
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    (SELECT DISTINCT city_group, region_code FROM dw_public.dim_region) AS dr
      ON rf.region_code = dr.region_code
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
agent_supports AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    'Other' AS demand_channel,
    NULL::BIGINT AS messages_sent_tta,
    COUNT(DISTINCT rf.tta_id) AS registered_agent_supports,
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
    rent_flows_adap AS rf
      ON DATE(rf.first_attendance_date) = dd.date
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
visits_booked AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    db.mkt_channel AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_booking_created_date
      AND rf.sk_booking_created_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN dw_public.dim_booking db
      ON rf.sk_booking = db.sk_booking
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
visits_completed AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    db.mkt_channel AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_visit_date
      AND rf.sk_visit_date > 0 AND rf.flg_visit_completed = 1
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN dw_public.dim_booking db
      ON rf.sk_booking = db.sk_booking
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
offer_submitted AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_offer_submitted_date
      AND rf.sk_offer_submitted_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
offer_approved AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_offer_approved_date
      AND rf.sk_offer_approved_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_evaluation_init AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_first_credit_evaluation_init
      AND rf.sk_first_credit_evaluation_init > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_evaluation_positive AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_first_credit_evaluation_positive
      AND rf.sk_first_credit_evaluation_positive > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
doc_sent AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_tenant_first_doc_sent_date
      AND rf.sk_tenant_first_doc_sent_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
doc_approved AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_last_doc_analysis_approved
      AND rf.sk_last_doc_analysis_approved > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
doc_completed AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    COUNT(DISTINCT rf.sk_offer) AS doc_completed,
    NULL::BIGINT AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_credit_analysis_init_date
      AND rf.sk_credit_analysis_init_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_processed AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    COUNT(DISTINCT rf.sk_offer) AS credit_processed,
    NULL::BIGINT AS credit_approved,
    NULL::BIGINT AS contract_created,
    NULL::BIGINT AS contract_signed,
    NULL::BIGINT AS contract_ended
  FROM 
    dw_public.dim_date AS dd
  JOIN 
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_credit_analysis_end_date
      AND rf.sk_credit_analysis_end_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
credit_approved AS(
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_credit_analysis_approved_date
      AND rf.sk_credit_analysis_approved_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_created AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_contract_created_date
      AND rf.sk_contract_created_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
    ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_signed AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
    NULL::BIGINT AS visits_booked,
    NULL::BIGINT AS messages_sent_tta,
    NULL::BIGINT AS registered_agent_supports,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_contract_signed_date
      AND rf.sk_contract_signed_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN 
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
contract_ended AS (
  SELECT
    dd.date,
    dd.sk_date,
    dr.city_group,
    dhl.is_b2b,
    rf.funnel_flow,
    rf.funnel_first_touchpoint,
    rf.had_flow_visit,
    rf.had_flow_direct,
    rf.had_flow_tta,
    rf.flow_type,
    dof.mkt_medium AS demand_channel,
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
    rent_flows_adap AS rf
      ON dd.sk_date = rf.sk_contract_annulment_date
      AND rf.sk_contract_signed_date > 0 and rf.sk_contract_annulment_date > 0
  JOIN 
    dw_public.dim_house_listing AS dhl
      ON rf.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN
    dw_public.dim_offer AS dof
      ON rf.sk_offer = dof.sk_offer
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON rf.sk_region = dr.sk_region
  WHERE 
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE() -- filter data from 4 years ago
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
union_all AS (
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
  SELECT * FROM doc_completed
  UNION ALL
  SELECT * FROM credit_processed
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
    ua.is_b2b,
    ua.funnel_flow,
    ua.funnel_first_touchpoint,
    ua.had_flow_visit,
    ua.had_flow_direct,
    ua.had_flow_tta,
    ua.flow_type,
    ua.demand_channel,
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
    ua.doc_completed,
    ua.credit_processed,
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
    dd.date BETWEEN DATE_TRUNC('year',CURRENT_TIMESTAMP()) - INTERVAL '4 year' AND CURRENT_DATE()
)
SELECT
  date,
  city_group,
  funnel_flow,
  funnel_first_touchpoint,
  had_flow_visit,
  had_flow_direct,
  had_flow_tta,
  flow_type,
  CASE 
    WHEN demand_channel IN ('Not Mapped', 'Other') 
        OR demand_channel IS null THEN 'Other'
    ELSE demand_channel 
  END AS demand_channel,
  is_b2b AS is_b2b_demand,
  SUM(messages_sent_tta) AS messages_sent_tta,
  SUM(registered_agent_supports) AS registered_agent_supports,
  SUM(visits_booked) AS visits_booked,
  SUM(visits_completed) AS visits_completed,
  SUM(offer_submitted) AS offer_submitted,
  SUM(offer_approved) AS offer_approved,
  SUM(COALESCE(credit_evaluation_init,0)) AS credit_evaluation_init,
  SUM(COALESCE(credit_evaluation_positive,0)) AS credit_evaluation_positive,
  SUM(doc_sent) AS doc_sent,
  SUM(COALESCE(doc_approved,0)) AS doc_approved,
  SUM(doc_completed) AS doc_completed,
  SUM(credit_processed) AS credit_processed,
  SUM(credit_approved) AS credit_approved,
  SUM(contract_created) AS contract_created,
  SUM(contract_signed) AS contract_signed,
  SUM(contract_ended) AS contract_ended,
  CURRENT_TIMESTAMP() AS ts_load
FROM 
  union_all
GROUP BY date, city_group, 3, 4, 5, 6, 7, 8, 9, 10 