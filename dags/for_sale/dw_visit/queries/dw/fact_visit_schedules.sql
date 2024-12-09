SELECT
  es.id_schedule AS sk_schedule,
  es.id_visit AS sk_visit,
  es.id_region AS sk_region,
  bc.sk_business_context,
  vm.sk_visit_model,
  db.sk_behavior_type,
  fup.sk_visit_fup,
  bm.sk_business_model,
  es.id_business_unit AS sk_business_unit,
  es.id_company_supply AS sk_company_supply,
  es.id_company_demand AS sk_company_demand,
  es.id_agent AS sk_agent,
  es.id_user_agent AS sk_user_agent,
  es.id_user_en AS sk_user_en,
  es.id_fixed_agent AS sk_fixed_agent,
  es.id_user_creation AS sk_author_creator,
  es.id_user_cancelation AS sk_author_cancelation,
  es.visit_code,
  es.id_offer AS sk_offer,
  et.sk_entrance_type,
  es.id_succeed_schedule AS sk_succeed_schedule,
  sk_origin_type,
  es.days_visit_cancelled_to_visit,
  es.days_visit_booked_to_visit,
  es.days_visit_booked_to_cancelled,
  es.days_visit_booked_to_visit_completed,
  es.hours_booking_to_offer,
  es.hours_visit_to_offer,
  CASE WHEN es.is_hub_flow IS TRUE THEN 1 ELSE 0 END AS is_hub_flow,
  CASE WHEN es.is_house_rented IS TRUE THEN 1 ELSE 0 END AS is_house_rented,
  CASE WHEN es.has_tenant_living IS TRUE THEN 1 ELSE 0 END AS has_tenant_living,
  1 AS is_booking,
  CASE WHEN es.ts_schedule_rescheduled IS NOT NULL THEN 1 ELSE 0 END AS is_reschedule,
  CASE WHEN es.ts_schedule_confirmed IS NOT NULL THEN 1 ELSE 0 END AS is_confirmed,
  CASE WHEN es.ts_schedule_completed IS NOT NULL THEN 1 ELSE 0 END AS is_completed,
  CASE WHEN es.ts_schedule_canceled IS NOT NULL THEN 1 ELSE 0 END AS is_canceled,
  CASE WHEN es.ts_schedule_unsuccessful IS NOT NULL THEN 1 ELSE 0 END AS is_unsuccessful,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_created,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_created,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_confirmed,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_confirmed,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_completed,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_completed,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_canceled,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_canceled,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_unsuccessful,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_unsuccessful,
  NOW() AS ts_load
FROM
  datalake_visit.visit_schedules AS es
INNER JOIN
   dw_visit.dim_origin_type AS dot
    ON es.schedule_origin = dot.origin_name
INNER JOIN
   dw_visit.dim_business_context AS bc
    ON es.business_context = bc.business_context
INNER JOIN
    dw_visit.dim_visit_model AS vm
     ON  es.visit_model = vm.visit_model
INNER JOIN
    dw_visit.dim_behavior AS db
        ON es.behavior = db.behavior_type
LEFT JOIN
    dw_visit.dim_entrance_type AS et
        ON es.method = et.entrance_type
LEFT JOIN
    dw_visit.dim_business_model AS bm
        ON es.business_model = bm.business_model
LEFT JOIN
    dw_visit.dim_visit_fup AS fup
        ON es.visit_fup = fup.visit_fup
