SELECT
  r.id_agent AS sk_agent,
  MD5(sad.department) AS sk_department,
  CAST(DATE_FORMAT(dt, 'yyyyMMdd') AS BIGINT) as sk_date,
  SUM(COALESCE(sum_csat_satisfied_score, 0)) AS total_csat_satisfied_score,
  SUM(COALESCE(sum_csat_dissatisfied_score, 0)) AS total_csat_dissatisfied_score,
  SUM(COALESCE(total_tickets_with_csat_score, 0)) AS total_tickets_with_csat_score,
  SUM(COALESCE(total_tickets_resolution, 0)) AS total_tickets_resolution,
  SUM(COALESCE(total_tickets_answered_resolution, 0)) AS total_tickets_answered_resolution,
  SUM(COALESCE(total_tickets, 0)) AS total_tickets,
  SUM(COALESCE(total_tickets_with_taxonomy, 0)) AS total_tickets_with_taxonomy,
  SUM(COALESCE(sum_ticket_resolution_time, 0)) AS total_minutes_resolution_time,
  SUM(COALESCE(total_crm_tasks_solved, 0)) AS total_crm_tasks_solved,
  MAX(agent_age_in_months) AS agent_age_in_months,
  dt AS dt_metric_reference,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_analyst_ranking.ranking r
JOIN
  datalake_gsheets_clean.support_agents_department sad
    ON r.id_agent = sad.id_agent
    AND dt BETWEEN sad.dt_start AND COALESCE(sad.dt_end, NOW())
WHERE
  r.id_agent IS NOT NULL
  AND year = {year}
  AND month = {month}
  AND day = {day}
GROUP BY 1,2,3,14,16,17,18