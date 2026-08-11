SELECT
  id,
  id_onboarding,
  id_task_type,
  reference_date_field,
  title,
  status,
  start_offset,
  end_offset,
  id_deleted,
  dt_started,
  dt_due,
  ts_created,
  ts_updated
FROM (
  SELECT
    id,
    id_onboarding,
    id_task_type,
    reference_date_field,
    title,
    status,
    start_offset,
    end_offset,
    id_deleted,
    dt_started,
    dt_due,
    ts_created,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
  FROM datalake_mission_control_clean.onboarding_task
) AS _t
WHERE
  _w = 1