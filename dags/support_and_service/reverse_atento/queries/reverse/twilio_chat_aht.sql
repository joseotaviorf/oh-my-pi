SELECT
  ca.dt_task_created_local,
  ca.agent_email,
  ca.department_name,
  ca.ts_start_first_task,
  ca.ts_end_last_task,
  ca.tasks,
  ca.average_concurrency,
  ca.average_handling_time_seconds,
  dc.team AS area_aux,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load
FROM
  datalake_customer_support.chat_aht ca
LEFT JOIN
  datalake_gsheets_clean.department_control dc
    ON ca.department_name = dc.department
    AND dc.channel = 'Twillio'
WHERE
  ca.dt_task_created_local BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  AND ca.agent_organization IN ("atento", "atn")
