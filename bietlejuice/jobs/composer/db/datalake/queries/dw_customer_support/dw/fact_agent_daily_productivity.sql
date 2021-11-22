SELECT
  id_agent AS sk_agent,
  MD5(agent_manager) AS sk_agent_manager,
  MD5(department) AS sk_department,
  CAST(DATE_FORMAT(dt, 'yyyyMMdd') AS BIGINT) as sk_date,
  sum_csat_satisfied_score AS total_csat_satisfied_score,
  sum_csat_dissatisfied_score AS total_csat_dissatisfied_score,
  total_tickets_with_csat_score,
  total_tickets_resolution,
  total_tickets_answered_resolution,
  total_tickets,
  total_tickets_with_taxonomy,
  sum_ticket_resolution_time AS total_minutes_resolution_time,
  total_tasks_solved_crm,
  agent_age_in_months,
  dt,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_analyst_ranking.ranking
WHERE
  dt = DATE('{year}-{month}-{day}')