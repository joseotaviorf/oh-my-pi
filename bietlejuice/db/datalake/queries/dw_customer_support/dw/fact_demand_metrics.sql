SELECT
  COALESCE(dm.id_agent, bm.id_agent) AS sk_agent,
  MD5(COALESCE(dm.type, bm.type)) AS sk_demand_type,
  CAST(REPLACE(COALESCE(dm.dt_metric_reference, bm.dt_metric_reference), '-', '') AS BIGINT) AS sk_metric_reference_date,
  SUBSTRING(COALESCE(dm.type, bm.type), 1, 100) AS demand_type,  
  dm.received_demand,
  dm.solved_demand,
  dm.tickets_solved_in_time AS tickets_solved_within_sla,
  dm.tickets_not_solved_in_time AS tickets_solved_with_exceed_sla,
  dm.time_spent_on_tickets_solved_in_time AS days_spent_on_solved_tickets_within_sla,
  dm.time_spent_on_tickets_not_solved_in_time AS days_spent_on_solved_tickets_with_exceed_sla,
  dm.total_time_spent AS total_days_spent,
  bm.daily_backlog,
  bm.backlog_in_time AS backlog_within_sla,
  bm.backlog_not_in_time AS backlog_with_exceed_sla,
  bm.is_sunday,
  COALESCE(dm.dt_metric_reference, bm.dt_metric_reference) AS dt_metric_reference,
  NOW() AS ts_load
FROM
  datalake_customer_demand.demand_metrics dm
FULL OUTER JOIN
  datalake_customer_demand.backlog_metrics bm
    ON dm.id_agent = bm.id_agent
    AND dm.type = bm.type
    AND dm.dt_metric_reference = bm.dt_metric_reference