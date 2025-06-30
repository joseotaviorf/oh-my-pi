SELECT
    id_schedule AS sk_schedule,
    schedule_origin,
    channel_creation,
    IF(id_succeed_schedule IS NULL, TRUE, FALSE) AS is_last_schedule,
    IF(schedule_origin = "REQUEST", TRUE, FALSE) AS is_first_schedule,
    ts_schedule_created,
    ts_schedule_requested,
    ts_schedule_rescheduled,
    ts_schedule_confirmed,
    ts_schedule_completed,
    ts_schedule_unsuccessful,
    ts_schedule_canceled
  FROM
    datalake_visit.visit_schedules
