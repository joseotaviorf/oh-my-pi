WITH visit_tenant_living AS (
  WITH visit_tenant_living_ranked AS (
    SELECT
      v.id_visit,
      fc.sk_contract AS sk_contract_tenant_living,
      fc.sk_tenant AS sk_tenant_living,
      ROW_NUMBER() OVER(PARTITION BY v.id_visit ORDER BY dc.dt_start DESC) AS rn
    FROM
      datalake_visit.visits AS v
    JOIN
      dw_rent.fact_contracts AS fc
        ON v.id_house = fc.sk_house
    JOIN
      dw_rent.dim_contract dc
        ON fc.sk_contract = dc.sk_contract
        AND dc.status IN ('Ativo', 'Finalizado')
        AND DATE(v.ts_visit) >= dc.dt_start
        AND DATE(v.ts_visit) < COALESCE(dc.dt_annulment, CURRENT_DATE)
  )
  SELECT
    id_visit,
    sk_contract_tenant_living,
    sk_tenant_living
  FROM
    visit_tenant_living_ranked
  WHERE
    rn = 1
)
SELECT
  v.id_visit AS sk_visit,
  v.id_last_schedule AS sk_last_schedule,
  v.id_visit_cycle AS sk_visit_cycle,
  v.id_visit_attempt_cycle AS sk_visit_attempt_cycle,
  v.id_visitor AS sk_visitor,
  v.id_owner AS sk_owner,
  v.id_user_visit_request AS sk_user_visit_request,
  v.id_first_associated_agent AS sk_first_associated_agent,
  v.id_last_associated_agent AS sk_last_associated_agent,
  v.id_user_agent_vbba AS sk_user_agent_vbba,
  pfa.id_agent AS sk_fixed_agent,
  pfa.id_user_agent AS sk_user_fixed_agent,
  v.id_house AS sk_house,
  vtl.sk_contract_tenant_living AS sk_contract_tenant_living,
  vtl.sk_tenant_living AS sk_tenant_living,
  h.id_region AS sk_region,
  v.id_house_listing AS sk_house_listing,
  COALESCE(v.sk_broker_supply, -1) AS sk_broker_supply,
  COALESCE(v.sk_broker_demand, -1) AS sk_broker_demand,
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
  CAST(v.is_confirmed_last_schedule AS INTEGER) AS num_visit_confirmed_last_schedule,
  CAST(v.is_completed AS INTEGER) AS num_visit_completed,
  CAST(v.is_canceled AS INTEGER) AS num_visit_canceled,
  CAST(v.is_unsuccessful AS INTEGER) AS num_visit_unsuccessful,
  CAST(v.is_stalled AS INTEGER) AS num_visit_stalled,
  IF(funnel_os.sk_visit_funnel IS NOT NULL, 1, 0) AS num_offer_submitted,
  IF(funnel_oa.sk_visit_funnel IS NOT NULL, 1, 0) AS num_offer_accepted,
  IF(funnel_cs.sk_visit_funnel IS NOT NULL, 1, 0) AS num_contract_signed,
  IF(pvd.sk_visit IS NOT NULL, 1, 0) num_post_visit_demand,
  CAST(pvd.is_visit_completed_by_demand AS INTEGER) AS num_visit_completed_by_demand,
  CAST(NOT pvd.is_visit_completed_by_demand AS INTEGER) AS num_visit_unsuccessful_by_demand,
  CAST(pvd.is_visit_canceled_by_demand AS INTEGER) AS num_visit_canceled_by_demand,
  CAST(NOT pvd.is_visit_canceled_by_demand AS INTEGER) AS num_visit_not_canceled_by_demand,
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
  CASE
    WHEN v.business_context = 'SALE' THEN lst.sale_type
  END AS sale_type,
  v.journey_days,
  TIMESTAMPDIFF(HOUR, v.ts_created, (v.ts_visit_local_tz + INTERVAL 3 HOUR)) AS hours_between_created_and_visit_day,
  TIMESTAMPDIFF(HOUR, v.ts_created, v.ts_visit_canceled) AS hours_between_request_and_cancellation,
  TIMESTAMPDIFF(HOUR, v.ts_visit_first_confirmed, v.ts_visit_canceled) AS hours_between_first_booked_and_visit_day,
  TIMESTAMPDIFF(HOUR, v.ts_visit_last_confirmed, v.ts_visit_canceled) AS hours_between_last_booked_and_visit_day,
  TIMESTAMPDIFF(HOUR, v.ts_visit_canceled, (v.ts_visit_local_tz + INTERVAL 3 HOUR)) AS hours_between_cancellation_and_visit_date,
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
LEFT JOIN
  datalake_ebdb_listing.house AS h
    ON h.id = v.id_house
LEFT JOIN
  datalake_region.region AS r
    ON h.id_region = r.id
LEFT JOIN
  datalake_ebdb_agents.preferred_fixed_agent_history AS pfa
    ON v.id_visitor = pfa.id_visitor
    AND r.id_city = pfa.id_region
    AND v.business_context = pfa.business_context
    AND v.ts_created BETWEEN pfa.ts_status_started AND COALESCE(pfa.ts_status_ended, NOW())
LEFT JOIN
  visit_tenant_living AS vtl
    ON v.id_visit = vtl.id_visit
LEFT JOIN
  datalake_sale_primary_market.listing_sale_type AS lst
    ON lst.id_house = v.id_house
