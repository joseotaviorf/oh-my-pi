WITH
    ranking AS (
        SELECT
            id_visit,
            id_schedule,
            event_type,
            ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY ts_created ASC) AS ranking,
            ts_created AS ts_event_created
        FROM
            datalake_ebdb_clean.visit_status_log
    ),
    reschedules AS (
      SELECT
        ev1.id_schedule AS id_schedule,
        ev2.id_schedule AS id_succeed_schedule
      FROM
        ranking AS ev1
      INNER JOIN
        ranking AS ev2
        ON ev1.id_visit = ev2.id_visit
        AND ev1.ranking = (ev2.ranking-1)
        AND ev2.event_type = 'VISIT_RESCHEDULED'
      GROUP BY ALL
    ),
   visit_model AS (
      SELECT
        id_visit,
        CASE
          WHEN vse.event_type = 'VISIT_FITTED' THEN 'FITTED'
          WHEN vse.event_type = 'VISIT_REGISTERED' THEN 'REGISTERED'
        END AS visit_model
      FROM
        datalake_ebdb_clean.visit_status_log AS vse
      WHERE
        vse.event_type IN ('VISIT_FITTED', 'VISIT_REGISTERED')
      GROUP BY ALL
    )
SELECT
  vse.id_schedule,
  vse.id_visit,
  MIN_BY(id_author_user, vse.ts_created) AS id_author_creator,
  reschedules.id_succeed_schedule,
  business_context,
  CASE
    WHEN vm.visit_model IS NULL THEN 'STANDARD'
    ELSE vm.visit_model
  END AS visit_model,
  CASE
    WHEN MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') IS NULL THEN 'RESCHEDULE'
    ELSE 'REQUEST'
  END AS schedule_origin,
  MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS ts_schedule_requested,
  MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_RESCHEDULED') AS ts_schedule_rescheduled,
  MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_CONFIRMED') AS ts_schedule_confirmed,
  MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_DONE') AS ts_schedule_completed,
  MIN(vse.ts_created) FILTER (WHERE event_type = 'VISIT_UNSUCCESSFUL') AS ts_schedule_unsuccessful,
  MAX(vse.ts_created) FILTER (WHERE event_type IN ('VISIT_REQUEST_CANCELED', 'VISIT_CANCELED')) AS ts_schedule_canceled
FROM
  datalake_ebdb_clean.visit_status_log AS vse
LEFT JOIN
  datalake_ebdb_clean.visit AS v
    ON vse.id_visit = v.id
LEFT JOIN
  reschedules
    ON reschedules.id_schedule = vse.id_schedule
LEFT JOIN
    visit_model AS vm
        ON vse.id_visit = vm.id_visit
GROUP BY
  vse.id_schedule,
  vse.id_visit,
  business_context,
  visit_model,
  id_succeed_schedule
HAVING
    MIN(vse.ts_created) >= '2024-11-01'
