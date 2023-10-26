SELECT
  id_task AS sk_task,
  id_agent AS sk_agent,
  id_taxonomy AS sk_taxonomy,
  id_tags AS sk_tags,
  id_main_department AS sk_main_department,
  sla_target,
  origin,
  status,
  time_spent_solved_in_time AS time_spent_solved_within_sla,
  time_spent_not_solved_in_time AS time_spent_solved_with_exceed_sla,
  days_worked,
  days_off,
  is_ticket_solved_in_time AS is_ticket_solved_within_sla,
  is_ticket_not_solved_in_time AS is_ticket_solved_with_exceed_sla,
  is_received_demand,
  is_solved_demand,
  is_closed_demand,
  ts_started,
  ts_completed AS ts_solved,
  ts_closed,
  NOW() AS ts_load
FROM
  datalake_customer_demand.demand_metrics_tasks
