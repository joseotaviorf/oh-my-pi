WITH tickets_info AS (
  SELECT DISTINCT
    id_ticket,
    id_agent,
    agent_company,
    agent_manager,
    department,
    minutes_full_resolution_time_business,
    DATE(email.ts_ticket_solved) AS dt_ticket_solved
  FROM
    datalake_customer_support.email
),
ticket_metrics AS (
  SELECT
    id_agent,
    agent_company,
    agent_manager,
    dt_ticket_solved AS dt,
    department,
    COUNT(DISTINCT id_ticket) AS total_tickets,
    SUM(minutes_full_resolution_time_business) AS sum_ticket_resolution_time
  FROM
    tickets_info
  WHERE
    dt_ticket_solved = DATE('{year}-{month}-{day}')
  GROUP BY 1,2,3,4,5
),
csat(
  WITH first_csat_response AS (
    SELECT 
      id_ticket,
      MIN(ts_response) AS ts_fisrt_response
    FROM
      datalake_customer_support.csat csat
    GROUP BY 1
  )
  SELECT
    id_agent,
    agent_company,
    agent_manager,
    department,
    DATE(csat.ts_response) AS dt,
    SUM(CASE WHEN csat.csat_score >= 4 THEN 1 ELSE 0 END) AS sum_csat_score,
    SUM(CAST(csat.resolution_survey = TRUE AS SMALLINT)) AS total_tickets_resolution,
    SUM(CAST(csat.resolution_survey IS NOT NULL AS SMALLINT)) AS total_tickets_answered_resolution,
    SUM(CAST(csat.csat_score IS NOT NULL AS SMALLINT)) AS total_tickets_with_csat_score
  FROM
    datalake_customer_support.csat csat
  JOIN
    first_csat_response fc
      ON csat.id_ticket = fc.id_ticket
      AND csat.ts_response = fc.ts_fisrt_response
  JOIN
    tickets_info tickets
      ON tickets.id_ticket = csat.id_ticket
  WHERE
    DATE(csat.ts_response) = DATE('{year}-{month}-{day}')
  GROUP BY 1,2,3,4,5
)
SELECT
  COALESCE(ztm.id_agent, csat.id_agent) AS id_agent,
  COALESCE(ztm.agent_company, csat.agent_company) AS agent_company,
  COALESCE(ztm.agent_manager, csat.agent_manager) AS agent_manager,
  COALESCE(ztm.department, csat.department) AS department,
  csat.sum_csat_score,
  csat.total_tickets_resolution,
  csat.total_tickets_answered_resolution,
  csat.total_tickets_with_csat_score,
  ztm.total_tickets,
  ztm.sum_ticket_resolution_time,
  CAST(CEIL(MONTHS_BETWEEN(COALESCE(ztm.dt, csat.dt), ac.dt_start)) AS INT) AS agent_age_in_months,
  COALESCE(ztm.dt, csat.dt) AS dt,
  YEAR(COALESCE(ztm.dt, csat.dt)) AS year,
  MONTH(COALESCE(ztm.dt, csat.dt)) AS month,
  DAY(COALESCE(ztm.dt, csat.dt)) AS day
FROM
  ticket_metrics ztm
FULL OUTER JOIN
  csat
    ON ztm.id_agent = csat.id_agent
    AND ztm.department = csat.department
    AND ztm.dt = csat.dt
JOIN
  datalake_gsheets_clean.agents_control ac
    ON ac.id_assignee = COALESCE(ztm.id_agent, csat.id_agent)