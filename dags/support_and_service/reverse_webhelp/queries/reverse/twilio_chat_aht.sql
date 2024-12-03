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
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  datalake_quinto_messenger.chat_aht AS ca
  LEFT JOIN
    datalake_gsheets_clean.department_control AS dc
      ON ca.department_name = dc.department
      AND dc.channel = 'Twillio'
WHERE
  ca.dt_task_created_local BETWEEN DATE('{load_start_date}') - 1 AND DATE('{load_end_date}')
  AND ca.agent_organization IN ('webhelp', 'webhelpbr')
