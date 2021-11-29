WITH tickets_info AS (
  SELECT DISTINCT
    id_ticket,
    id_agent,
    agent_company,
    agent_manager,
    department,
    minutes_full_resolution_time_business,
    CASE 
      WHEN 
        customer_type_tag IS NOT NULL 
        AND contact_motivation_tag IS NOT NULL 
        AND contact_theme_tag IS NOT NULL 
      THEN TRUE 
      ELSE FALSE
    END AS is_taxonomy_filled,
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
    SUM(CAST(is_taxonomy_filled AS SMALLINT)) AS total_tickets_with_taxonomy,
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
    SUM(CASE WHEN csat.csat_score >= 4 THEN 1 ELSE 0 END) AS sum_csat_satisfied_score,
    SUM(CASE WHEN csat.csat_score < 3 THEN 1 ELSE 0 END) AS sum_csat_dissatisfied_score,
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
),
crm_metrics AS (
  WITH last_updated_task AS (
      SELECT
          id_task,
          MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated
      FROM
          datalake_crm_tasks_flows.tasks_actions_resolutions_flow
      GROUP BY 1
  )
  SELECT
    ac.id_assignee AS id_agent,
    DATE(tarf.ts_completed) AS dt,
    COUNT(1) AS total_tasks_solved_crm
  FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow turf
  JOIN
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow tarf  
      ON tarf.id_task = turf.id_task
  JOIN
    last_updated_task lut
      ON lut.id_task = tarf.id_task
      AND lut.dt_last_updated = DATE(CONCAT(tarf.year, '-', tarf.month, '-', tarf.day))
  LEFT JOIN
    datalake_ebdb_user.user du
      ON du.id = turf.id_assignee
  LEFT JOIN
    datalake_gsheets_clean.agents_control ac
      ON ac.email = du.email
  LEFT JOIN
    datalake_terminator_clean.termination t
      ON t.id_contract = turf.id_contract
  LEFT JOIN
    datalake_terminator_clean.termination_workflow tw
      ON t.id = tw.id
  WHERE
    turf.type IN (
      'RevisarPagamentosRescisao',
      'RescisaoPreVigencia'
    )
    AND LOWER(turf.action_type) = 'realize'
    AND DATE(tarf.ts_completed) = DATE('{year}-{month}-{day}')
  GROUP BY 1,2
)
SELECT
  COALESCE(ztm.id_agent, csat.id_agent, crm.id_agent) AS id_agent,
  ac.agent_company,
  ac.manager AS agent_manager,
  CASE 
    WHEN 
      COALESCE(ztm.department, csat.department) IN (
        'Offboarding [OFF] [POS] [BACK]', 
        'Proteção QuintoAndar [OFF] [POS] [BACK]', 
        'Rescisão - Despejo [OFF][POS][BACK]', 
        'Offboarding Reparos [OFF] [POS] [BACK]'
      )
      OR COALESCE(ztm.department, csat.department) IS NULL
      THEN aro.ranking
    ELSE COALESCE(ztm.department, csat.department) 
  END AS department,
  SUM(csat.sum_csat_satisfied_score) AS sum_csat_satisfied_score,
  SUM(csat.sum_csat_dissatisfied_score) AS sum_csat_dissatisfied_score,
  SUM(csat.total_tickets_resolution) AS total_tickets_resolution,
  SUM(csat.total_tickets_answered_resolution) AS total_tickets_answered_resolution,
  SUM(csat.total_tickets_with_csat_score) AS total_tickets_with_csat_score,
  SUM(ztm.total_tickets) AS total_tickets,
  SUM(ztm.total_tickets_with_taxonomy) AS total_tickets_with_taxonomy,
  SUM(ztm.sum_ticket_resolution_time) AS sum_ticket_resolution_time,
  SUM(crm.total_tasks_solved_crm) AS total_crm_tasks_solved,
  CAST(CEIL(MONTHS_BETWEEN(COALESCE(ztm.dt, csat.dt, crm.dt), ac.dt_start)) AS INT) AS agent_age_in_months,
  COALESCE(ztm.dt, csat.dt, crm.dt) AS dt,
  YEAR(COALESCE(ztm.dt, csat.dt, crm.dt)) AS year,
  MONTH(COALESCE(ztm.dt, csat.dt, crm.dt)) AS month,
  DAY(COALESCE(ztm.dt, csat.dt, crm.dt)) AS day
FROM
  ticket_metrics ztm
FULL OUTER JOIN
  csat
    ON ztm.id_agent = csat.id_agent
    AND ztm.department = csat.department
    AND ztm.dt = csat.dt
FULL OUTER JOIN
  crm_metrics crm
    ON crm.id_agent = COALESCE(ztm.id_agent, csat.id_agent)
    AND crm.dt = COALESCE(ztm.dt, csat.dt)
JOIN
  datalake_gsheets_clean.agents_control ac
    ON ac.id_assignee = COALESCE(ztm.id_agent, csat.id_agent, crm.id_agent)
LEFT JOIN
  datalake_gsheets_clean.agents_ranking_offboarding aro
    ON ac.email = aro.email
    AND COALESCE(ztm.dt, csat.dt, crm.dt) BETWEEN aro.dt_start AND COALESCE(aro.dt_end, DATE(NOW()))
GROUP BY 1,2,3,4,14,15,16,17