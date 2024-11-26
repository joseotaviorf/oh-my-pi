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
    )
SELECT
  vse.id_schedule,
  id_visit,
  MIN_BY(id_author_user, ts_event_created) AS id_author_creator,
  reschedules.id_succeed_schedule,
  business_context,
  CASE
    WHEN MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') IS NULL THEN 'RESCHEDULE'
    ELSE 'REQUEST'
  END AS schedule_origin,
  MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS ts_schedule_requested,
  MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_schedule_rescheduled,
  MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_CONFIRMED') AS ts_schedule_confirmed,
  MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_DONE') AS ts_schedule_completed,
  MIN(ts_event_created) FILTER (WHERE event_type = 'VISIT_UNSUCCESSFUL') AS ts_schedule_unsuccessful,
  MAX(ts_event_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED')) AS ts_schedule_canceled
FROM
  datalake_visit.visit_status_events AS vse
LEFT JOIN
  reschedules
    ON reschedules.id_schedule = vse.id_schedule
GROUP BY
  vse.id_schedule,
  id_visit,
  business_context,
  id_succeed_schedule
