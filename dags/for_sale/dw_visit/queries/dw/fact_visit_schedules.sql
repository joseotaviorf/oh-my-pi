WITH
    reschedules AS (
      SELECT
        ev1.id_schedule AS id_schedule,
        ev2.id_schedule AS id_succeed_schedule
      FROM
        datalake_visit.visit_status_events AS ev1
      INNER JOIN
        datalake_visit.visit_status_events AS ev2
        ON ev1.id_visit = ev2.id_visit
        AND ev1.ranking = (ev2.ranking-1)
        AND ev2.event_type = 'VISIT_RESCHEDULED'
      GROUP BY ALL
    ),
    schedule_events AS
      (SELECT
        id_schedule,
        id_visit,
        MIN_BY(id_author_user, ts_event_created) AS id_author_creator,
        business_context,
        CASE
          WHEN MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') IS NULL THEN 'RESCHEDULE'
          ELSE 'REQUEST'
        END AS schedule_origin,
        MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS ts_schedule_requested,
        MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_schedule_rescheduled,
        MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_CONFIRMED') AS ts_schedule_confirmed,
        MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_DONE') AS ts_schedule_completed,
        MAX(ts_event_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED')) AS ts_schedule_canceled
       FROM
        datalake_visit.visit_status_events
      GROUP BY
        id_schedule,
        id_visit,
        business_context
)
SELECT
  schedule_events.id_schedule AS sk_schedule,
  id_visit AS sk_visit,
  id_author_creator AS sk_author_creator,
  bc.sk_business_context,
  reschedules.id_succeed_schedule AS sk_succeed_schedule,
  sk_origin_type,
  CASE WHEN ts_schedule_rescheduled IS NOT NULL THEN 1 ELSE 0 END AS is_reschedule,
  CASE WHEN ts_schedule_confirmed IS NOT NULL THEN 1 ELSE 0 END AS is_confirmed,
  CASE WHEN ts_schedule_completed IS NOT NULL THEN 1 ELSE 0 END AS is_completed,
  CASE WHEN ts_schedule_canceled IS NOT NULL THEN 1 ELSE 0 END AS is_canceled,
  COALESCE(CAST(REPLACE(SUBSTRING(COALESCE(ts_schedule_requested, ts_schedule_rescheduled),1, 10),'-','') AS BIGINT), -1) AS sk_schedule_created,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_confirmed,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_confirmed,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_completed,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_completed,
  COALESCE(CAST(REPLACE(SUBSTRING(ts_schedule_canceled,1, 10),'-','') AS BIGINT), -1) AS sk_schedule_canceled,
  NOW() AS ts_load
FROM
  schedule_events
LEFT JOIN
  reschedules
    ON reschedules.id_schedule = schedule_events.id_schedule
INNER JOIN
   dw_visit.dim_origin_type AS dot
    ON schedule_events.schedule_origin = dot.origin_name
LEFT JOIN
   dw_visit.dim_business_context AS bc
    ON schedule_events.business_context = bc.business_context
