SELECT
  v.id_visit AS sk_visit,
  v.id_visitor AS sk_visitor,
  v.id_owner AS sk_owner,
  v.id_user_visit_request AS sk_user_visit_request,
  v.id_first_associated_agent AS sk_first_associated_agent,
  v.id_last_associated_agent AS sk_last_associated_agent,
  v.id_house AS sk_house,
  v.id_house_listing AS sk_house_listing,
  v.id_company_demand AS sk_company_demand,
  v.id_company_supply AS sk_company_supply,
  ppa.id_house_listing_relation AS sk_ppa_relation,
  bc.sk_business_context,
  dim_heh.sk_house_entrance,
  dvs.sk_visit_status,
  funnel_os.sk_visit_funnel AS sk_funnel_offer_submitted,
  funnel_oa.sk_visit_funnel AS sk_funnel_offer_accepted,
  funnel_cs.sk_visit_funnel AS sk_funnel_contract_signed,
  pvd.sk_visit AS sk_post_visit_demand,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_requested,1, 10),'-','') AS BIGINT), -1) AS sk_visit_request_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_created,1, 10),'-','') AS BIGINT), -1) AS sk_visit_created_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_local_tz,1, 10),'-','') AS BIGINT), -1) AS sk_visit_date_local_tz,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_first_confirmed,1, 10),'-','') AS BIGINT), -1) AS sk_first_visit_confirmed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_last_confirmed,1, 10),'-','') AS BIGINT), -1) AS sk_last_visit_confirmed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_first_rescheduled,1, 10),'-','') AS BIGINT), -1) AS sk_first_visit_reschedule_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_rescheduled,1, 10),'-','') AS BIGINT), -1) AS sk_last_visit_reschedule_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_done,1, 10),'-','') AS BIGINT), -1) AS sk_visit_done,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_canceled,1, 10),'-','') AS BIGINT), -1) AS sk_visit_canceled,
  v.nbr_reschedule,
  nbr_reschedule+1 AS nbr_bookings,
  1 AS num_visit_booked,
  v.nbr_agent AS num_agents_associated,
  CAST(v.is_confirmed AS INTEGER) AS num_visit_confirmed,
  CAST(v.is_completed AS INTEGER) AS num_visit_completed,
  CAST(v.is_canceled AS INTEGER) AS num_visit_canceled,
  CAST(v.is_unsuccessful AS INTEGER) AS num_visit_unsuccessful,
  v.is_confirmed,
  v.is_completed,
  v.is_registered,
  v.is_reschedule,
  v.is_canceled,
  v.is_unsuccessful,
  v.is_3p_supply,
  v.is_3p_demand,
  v.is_3p_lead_gen,
  v.has_3p_access_control,
  v.journey_days,
  DATEDIFF(HOUR, v.ts_created, (v.ts_visit_local_tz + INTERVAL 3 HOUR)) AS hours_between_created_and_visit_day,
  DATEDIFF(HOUR, v.ts_created, v.ts_visit_canceled) AS hours_between_request_and_cancellation,
  DATEDIFF(HOUR, v.ts_visit_first_confirmed, v.ts_visit_canceled) AS hours_between_first_booked_and_visit_day,
  DATEDIFF(HOUR, v.ts_visit_last_confirmed, v.ts_visit_canceled) AS hours_between_last_booked_and_visit_day,
  DATEDIFF(HOUR, v.ts_visit_canceled, (v.ts_visit_local_tz + INTERVAL 3 HOUR)) AS hours_between_cancellation_and_visit_date,
  v.hours_waiting_for_answers,
  v.is_waiting_for_response,
  v.ts_visit_requested,
  v.ts_created AS ts_visit_created,
  v.ts_visit_local_tz,
  v.ts_visit_first_confirmed AS ts_first_visit_confirmed,
  v.ts_visit_last_confirmed AS ts_last_visit_confirmed,
  v.ts_visit_first_rescheduled AS ts_first_visit_rescheduled,
  v.ts_visit_rescheduled AS ts_last_visit_rescheduled,
  v.ts_visit_done,
  v.ts_visit_canceled,
  NOW() AS ts_load
FROM
  datalake_visit.visits AS v
LEFT JOIN
  dw_visit.dim_visit_status AS dvs
    ON v.computed_status = dvs.status_name
LEFT JOIN
  dw_visit.dim_business_context AS bc
    ON v.business_context = bc.business_context
LEFT JOIN
  dw_house.dim_house_entrance_history AS dim_heh
    ON v.id_house = dim_heh.sk_house
    AND v.ts_visit >= dim_heh.ts_entrance_started
    AND IF(v.ts_visit > NOW(), NOW(), v.ts_visit) < COALESCE(dim_heh.ts_entrance_ended, DATE_ADD(MINUTE, 1, NOW()))
LEFT JOIN
  dw_visit.dim_visit_funnel AS funnel_os
    ON v.id_visit = funnel_os.sk_visit
    AND v.business_context = funnel_os.business_context
    AND funnel_os.event_code = 'os'
LEFT JOIN
  dw_visit.dim_visit_funnel AS funnel_oa
    ON v.id_visit = funnel_oa.sk_visit
    AND v.business_context = funnel_oa.business_context
    AND funnel_oa.event_code = 'oa'
LEFT JOIN
  dw_visit.dim_visit_funnel AS funnel_cs
    ON v.id_visit = funnel_cs.sk_visit
    AND v.business_context = funnel_cs.business_context
    AND funnel_cs.event_code = 'cs'
LEFT JOIN
  datalake_ebdb_agents.preferred_property_agent_relation_history AS ppa
    ON ppa.id_house = v.id_house
    AND v.business_context = ppa.business_context
    AND v.ts_created BETWEEN ppa.ts_relation_started AND COALESCE(ppa.ts_relation_ended, NOW())
LEFT JOIN
  dw_visit.dim_post_visit_demand AS pvd
    ON v.id_visit = pvd.sk_visit
