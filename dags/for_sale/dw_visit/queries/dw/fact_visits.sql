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
  bc.sk_business_context,
  et.sk_entrance_type,
  bm.sk_business_model,
  db.sk_behavior_type,
  dvs.sk_visit_status,
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
    dw_visit.dim_entrance_type AS et
        ON v.method = et.entrance_type
LEFT JOIN
    dw_visit.dim_business_model AS bm
        ON v.business_model = bm.business_model
