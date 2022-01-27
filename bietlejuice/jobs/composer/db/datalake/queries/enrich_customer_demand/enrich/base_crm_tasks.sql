WITH termination_finished AS (
  SELECT
    ta.id,
    MAX(
      CASE 
        WHEN ta.ts_updated <= '2020-07-07' THEN n.ts_updated
        ELSE ta.ts_updated
      END
    ) AS ts_termination_finished
  FROM
    datalake_terminator_clean.termination_aud ta
  LEFT JOIN
    datalake_terminator_clean.negotiation n
      ON n.id_termination = ta.id
  WHERE
    status = 'DONE'
  GROUP BY 1
),
last_updated_task AS (
  SELECT
    id_task,
    MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated
  FROM
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow
  GROUP BY 1
)
SELECT
  tarf.id_task,
  turf.id_contract,
  tarf.type,
  turf.action_type,
  tarf.is_resolved,
  MAX(tm.dt_termination) AS dt_termination,
  tarf.ts_started,
  tarf.ts_completed,
  MIN(tm.ts_created) AS ts_termination_requested,
  MAX(tf.ts_termination_finished) AS ts_termination_finished
FROM 
  datalake_crm_tasks_flows.tasks_actions_resolutions_flow tarf
JOIN
  last_updated_task lut
    ON tarf.id_task = lut.id_task
    AND DATE(CONCAT(year, '-', month, '-', day)) = lut.dt_last_updated
LEFT JOIN
  datalake_crm_tasks_flows.tasks_users_resolutions_flow turf
    ON tarf.id_task = turf.id_task
LEFT JOIN 
  datalake_terminator_clean.termination as tm
    ON turf.id_contract = tm.id_contract
LEFT JOIN 
  termination_finished tf
    ON tf.id = tm.id
WHERE
  tarf.type = 'RevisarPagamentosRescisao'
  AND turf.action_type = 'CREATE'
GROUP BY 1,2,3,4,5,7,8