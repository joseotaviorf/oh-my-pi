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
  v.nbr_reschedule,
  nbr_reschedule+1 AS nbr_bookings,
  1 AS num_visit_booked,
  v.nbr_agent AS num_agents_associated,
  CAST(v.is_confirmed AS INTEGER) AS num_visit_confirmed,
  CAST(v.is_completed AS INTEGER) AS num_visit_completed,
  CAST(v.is_canceled AS INTEGER) AS num_visit_canceled,
  CAST(v.is_unsuccessful AS INTEGER) AS num_visit_unsuccessful,
  v.has_3p_access_control,
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
    AND v.ts_visit < COALESCE(dim_heh.ts_entrance_ended, NOW())
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
