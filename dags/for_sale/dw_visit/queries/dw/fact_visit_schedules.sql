SELECT
  schedule_events.id_schedule AS sk_schedule,
  id_visit AS sk_visit,
  id_author_creator AS sk_author_creator,
  bc.sk_business_context,
  schedule_events.id_succeed_schedule AS sk_succeed_schedule,
  sk_origin_type,
  CASE WHEN ts_schedule_rescheduled IS NOT NULL THEN 1 ELSE 0 END AS is_reschedule,
  CASE WHEN ts_schedule_confirmed IS NOT NULL THEN 1 ELSE 0 END AS is_confirmed,
  CASE WHEN ts_schedule_completed IS NOT NULL THEN 1 ELSE 0 END AS is_completed,
  CASE WHEN ts_schedule_canceled IS NOT NULL THEN 1 ELSE 0 END AS is_canceled,
  CASE WHEN ts_schedule_unsuccessful IS NOT NULL THEN 1 ELSE 0 END AS is_unsuccessful,
  COALESCE(CAST(REPLACE(SUBSTRING(COALESCE(ts_schedule_requested, ts_schedule_rescheduled),1, 10),'-','') AS BIGINT), -1) AS sk_schedule_created,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_confirmed,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_confirmed,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_completed,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_completed,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_canceled,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_canceled,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_unsuccessful,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_unsuccessful,
  NOW() AS ts_load
FROM
  datalake_visits.visit_schedules AS schedule_events
INNER JOIN
   dw_visit.dim_origin_type AS dot
    ON schedule_events.schedule_origin = dot.origin_name
LEFT JOIN
   dw_visit.dim_business_context AS bc
    ON schedule_events.business_context = bc.business_context
