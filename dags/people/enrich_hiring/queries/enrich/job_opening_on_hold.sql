WITH on_hold_events AS (
  SELECT
    id_event_target AS id_job_opening,
    id_close_reason_after_event AS id_close_reason,
    COALESCE(id_close_reason_after_event, -1) IN (4002187009, 4002188009) AS was_hold_start,
    COALESCE(id_close_reason_before_event, -1) IN (4002187009, 4002188009) AS was_hold_end,
    dt_closed_after_event AS dt_hold_started,
    ts_event
  FROM
    datalake_greenhouse_audit_log_clean.events
  WHERE
    id_close_reason_before_event IN (4002187009, 4002188009)
    OR id_close_reason_after_event IN (4002187009, 4002188009)
),
enrich_on_hold_events AS (
  SELECT
    id_job_opening,
    id_close_reason,
    CASE
      WHEN was_hold_start THEN ROW_NUMBER() OVER(
        PARTITION BY id_job_opening, was_hold_start ORDER BY ts_event
        )
    END AS hold_start_order,
    CASE
      WHEN was_hold_end THEN ROW_NUMBER() OVER(
        PARTITION BY id_job_opening, was_hold_end ORDER BY ts_event
        )
    END AS hold_end_order,
    was_hold_start,
    was_hold_end,
    CASE
      WHEN was_hold_start THEN COALESCE(dt_hold_started, CAST(ts_event AS DATE))
    END AS dt_hold_started,
    CASE
      WHEN was_hold_end THEN CAST(ts_event AS DATE)
    END AS dt_hold_ended,
    ts_event
  FROM
    on_hold_events
),
hold_ended_events AS (
  SELECT
    id_job_opening,
    hold_end_order,
    dt_hold_ended,
    ts_event
  FROM
    enrich_on_hold_events
  WHERE
    was_hold_end
)
SELECT
  start.id_job_opening,
  start.id_close_reason,
  open.code AS job_opening_code,
  close.name AS close_reason_name,
  start.hold_start_order AS event_order,
  DATE_DIFF(COALESCE(end.dt_hold_ended, DATE('{load_end_date}')), start.dt_hold_started) AS days_on_hold,
  start.dt_hold_started,
  COALESCE(end.dt_hold_ended, DATE('{load_end_date}')) AS dt_hold_ended,
  end.dt_hold_ended IS NULL AS is_currently_on_hold,
  COALESCE(end.ts_event, start.ts_event) AS ts_latest_event,
  NOW() AS ts_load
FROM
  enrich_on_hold_events AS start
LEFT JOIN
  hold_ended_events AS end
    ON start.id_job_opening = end.id_job_opening
    AND start.hold_start_order = end.hold_end_order
LEFT JOIN
  datalake_greenhouse_v3_clean.openings AS open
    ON open.id_opening = start.id_job_opening
LEFT JOIN
  datalake_greenhouse_v3_clean.close_reasons AS close
    ON close.id_close_reason = start.id_close_reason
WHERE
  start.was_hold_start
