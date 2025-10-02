WITH demand_relation AS (
  SELECT
    bm.id_visit,
    bm.business_model,
    cs.sk_company
  FROM
    datalake_visit.visit_business_model AS bm
  LEFT JOIN
    datalake_ebdb_clean.visitor AS vt
      ON bm.id_visit = vt.id_visit
      AND vt.type = 'Agent'
  LEFT JOIN
    datalake_company.company_sks AS cs
      ON vt.uuid_company = cs.uuid_company
)
SELECT
  fv.sk_visit,
  fv.sk_visitor,
  fv.sk_owner,
  fv.sk_first_associated_agent,
  fv.sk_last_associated_agent,
  fv.sk_house,
  fv.sk_house_listing,
  dr.sk_company AS sk_company_demand,
  fv.sk_company_supply,
  fv.sk_business_context,
  fv.sk_house_entrance,
  fv.sk_business_model,
  fv.sk_behavior_type,
  fv.sk_visit_status,
  fv.sk_funnel_offer_submitted,
  fv.sk_funnel_offer_accepted,
  fv.sk_funnel_contract_signed,
  fv.sk_visit_request_date,
  fv.sk_visit_created_date,
  fv.sk_visit_date_local_tz,
  fv.sk_first_visit_confirmed_date,
  fv.sk_last_visit_confirmed_date,
  fv.sk_first_visit_reschedule_date,
  fv.sk_last_visit_reschedule_date,
  fv.sk_visit_done,
  fv.sk_visit_canceled,
  dr.business_model,
  dcs.company_name AS company_name_supply,
  dcs.hubspot_company_tag AS hubspot_company_tag_supply,
  dcd.company_name AS company_name_demand,
  dcd.hubspot_company_tag AS hubspot_company_tag_demand,
  fv.nbr_reschedule,
  fv.nbr_bookings,
  fv.num_visit_booked,
  fv.num_agents_associated,
  fv.num_visit_confirmed,
  fv.num_visit_completed,
  fv.num_visit_canceled,
  fv.num_visit_unsuccessful,
  fv.journey_days,
  fv.hours_between_created_and_visit_day,
  fv.hours_between_request_and_cancellation,
  fv.hours_between_first_booked_and_visit_day,
  fv.hours_between_last_booked_and_visit_day,
  fv.hours_between_cancellation_and_visit_date,
  fv.hours_waiting_for_answers,
  fv.is_confirmed,
  fv.is_completed,
  fv.is_registered,
  fv.is_reschedule,
  fv.is_canceled,
  fv.is_unsuccessful,
  fv.is_waiting_for_response,
  fv.has_tenant_living,
  dr.business_model LIKE '3P' AS has_3p_access_control,
  fv.ts_visit_requested,
  fv.ts_visit_created,
  fv.ts_visit_local_tz,
  fv.ts_first_visit_confirmed,
  fv.ts_last_visit_confirmed,
  fv.ts_first_visit_rescheduled,
  fv.ts_last_visit_rescheduled,
  fv.ts_visit_done,
  fv.ts_visit_canceled,
  fv.ts_load
FROM
  dw_visit.fact_visits AS fv
LEFT JOIN
  demand_relation AS dr
    ON fv.sk_visit = dr.id_visit
LEFT JOIN
  dw_public.dim_company_3p_partners AS dcs
    ON fv.sk_company_supply = dcs.sk_company
LEFT JOIN
  dw_public.dim_company_3p_partners AS dcd
    ON dr.sk_company = dcd.sk_company