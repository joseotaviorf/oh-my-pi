WITH
  visit_status_events AS (
    SELECT
      id_visit,
      MIN_BY(id_agent, ts_event_created) AS sk_first_associated_agent,
      MAX_BY(id_agent, ts_event_created) AS sk_last_associated_agent,
      MIN(ts_event_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED') AS ts_first_confirmation,
      MAX(ts_event_created) FILTER (WHERE event_type = 'ANSWER_CONFIRMED') AS ts_last_confirmation,
      MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_first_reschedule,
      MAX(ts_event_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_last_reschedule,
      MAX(ts_event_created) FILTER (WHERE on_behalf_of = 'TENANT_LIVING') AS ts_event_tenant,
      MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_BOOKED' OR event_type = 'VISIT_CONFIRMED') AS ts_first_booked,
      MAX(ts_event_created) FILTER (WHERE event_type = 'VISIT_BOOKED' OR event_type = 'VISIT_CONFIRMED') AS ts_last_booked
      FROM
        datalake_visit.visit_status_events
      GROUP BY
        id_visit
  )
SELECT
  v.id_visit AS sk_visit,
  v.id_visitor AS sk_visitor,
  v.id_owner AS sk_owner,
  vse.sk_first_associated_agent,
  vse.sk_last_associated_agent,
  v.id_house AS sk_house,
  v.id_house_listing AS sk_house_listing,
  v.id_company_demand AS sk_company_demand,
  v.id_company_supply AS sk_company_supply,
  ppa.id_house_listing_relation AS sk_ppa_relation,
  bc.sk_business_context,
  dim_heh.sk_house_entrance,
  db.sk_behavior_type,
  dvs.sk_visit_status,
  funnel_os.sk_visit_funnel AS sk_funnel_offer_submitted,
  funnel_oa.sk_visit_funnel AS sk_funnel_offer_accepted,
  funnel_cs.sk_visit_funnel AS sk_funnel_contract_signed,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_requested,1, 10),'-','') AS BIGINT), -1) AS sk_visit_request_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_created,1, 10),'-','') AS BIGINT), -1) AS sk_visit_created_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_local_tz,1, 10),'-','') AS BIGINT), -1) AS sk_visit_date_local_tz,
  COALESCE(CAST(REPLACE(SUBSTRING(vse.ts_first_confirmation,1, 10),'-','') AS BIGINT), -1) AS sk_first_visit_confirmed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(vse.ts_last_confirmation,1, 10),'-','') AS BIGINT), -1) AS sk_last_visit_confirmed_date,
  COALESCE(CAST(REPLACE(SUBSTRING(vse.ts_first_reschedule,1, 10),'-','') AS BIGINT), -1) AS sk_first_visit_reschedule_date,
  COALESCE(CAST(REPLACE(SUBSTRING(vse.ts_last_reschedule,1, 10),'-','') AS BIGINT), -1) AS sk_last_visit_reschedule_date,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_done,1, 10),'-','') AS BIGINT), -1) AS sk_visit_done,
  COALESCE(CAST(REPLACE(SUBSTRING(v.ts_visit_canceled,1, 10),'-','') AS BIGINT), -1) AS sk_visit_canceled,
  v.ts_visit_requested,
  v.ts_created AS ts_visit_created,
  v.ts_visit_local_tz,
  vse.ts_first_confirmation AS ts_first_visit_confirmed,
  vse.ts_last_confirmation AS ts_last_visit_confirmed,
  vse.ts_first_reschedule AS ts_first_visit_rescheduled,
  vse.ts_last_reschedule AS ts_last_visit_rescheduled,
  v.ts_visit_done,
  v.ts_visit_canceled,
  v.nbr_reschedule,
  nbr_reschedule+1 AS nbr_bookings,
  v.is_waiting_for_response,
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
  v.journey_days,
  IF(sk_behavior_type IN (2,6,7), 1, 0) AS has_tenant_living,
  DATEDIFF(HOUR, v.ts_created, (v.ts_visit_local_tz + INTERVAL 3 HOUR)) AS hours_between_created_and_visit_day,
  DATEDIFF(HOUR, v.ts_created, v.ts_visit_canceled) AS hours_between_request_and_cancellation,
  DATEDIFF(HOUR, vse.ts_first_booked, v.ts_visit_canceled) AS hours_between_first_booked_and_visit_day,
  DATEDIFF(HOUR, vse.ts_last_booked, v.ts_visit_canceled) AS hours_between_last_booked_and_visit_day,
  DATEDIFF(HOUR, v.ts_visit_canceled, (v.ts_visit_local_tz + INTERVAL 3 HOUR)) AS hours_between_cancellation_and_visit_date,
  v.hours_waiting_for_answers,
  NOW() AS ts_load
FROM
  datalake_visit.visits AS v
INNER JOIN
  visit_status_events AS vse
    ON v.id_visit = vse.id_visit
INNER JOIN
  dw_visit.dim_behavior AS db
    ON v.behavior = db.behavior_type
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
