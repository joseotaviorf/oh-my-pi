SELECT
  id_task AS sk_task,
  MD5(agent_email) AS sk_agent,
  id_taxonomy AS sk_taxonomy,
  id_tags AS sk_tags,
  id_main_department AS sk_main_department,
  sla_target,
  origin,
  status,
  days_worked,
  days_worked_with_days_offs,
  days_off,
  is_daily_backlog,
  is_backlog_in_time AS is_backlog_within_sla,
  is_backlog_not_in_time AS is_backlog_with_exceed_sla,
  dt_metric_reference,
  ts_started,
  ts_completed AS ts_solved,
  NOW() AS ts_load
FROM
  datalake_customer_demand.backlog_metrics_tasks
