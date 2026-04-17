SELECT
  p.id_period,
  p.schedule_name,
  p.rotation_name,
  p.rotation_order,
  p.id_responder,
  p.responder_name,
  p.responder_email,
  p.id_responder <> p_base.id_responder AS is_overrided,
  IF(p.id_responder <> p_base.id_responder, p_base.id_responder, NULL) AS id_original_responder,
  IF(p.id_responder <> p_base.id_responder, p_base.responder_name, NULL) AS original_responder_name,
  IF(p.id_responder <> p_base.id_responder, p_base.responder_email, NULL) AS original_responder_email,
  p.ts_period_started,
  p.ts_period_ended,
  p.dt_load,
  p.year,
  p.month,
  p.day
FROM
  datalake_jira_schedules.periods AS p
LEFT JOIN
  datalake_jira_schedules.periods AS p_base
    ON p_base.id_period = p.id_period
    AND p_base.timeline_version = "base"
WHERE
  p.id_schedule IN ("9e63f54a-de9c-4e0d-bf48-75c95a28450d", "2fe05f0a-46ac-4b1c-8c20-fce1a9e5667b")
  AND p.timeline_version = "final"
  AND p.dt_load BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY p.id_period ORDER BY p.dt_load DESC) = 1