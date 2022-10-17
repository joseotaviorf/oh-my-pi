WITH contracts AS (
    SELECT
        turf.id_task,
        turf.id_start_date,
        turf.id_completed_date,
        COALESCE(ec.id, ev.id_contract, -1) AS id_contract,
        turf.action_type
    FROM
        datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
    LEFT JOIN
        datalake_ebdb_clean.contract AS ec
            ON turf.origin = 'Contrato'
            AND turf.id_origin = ec.id
    LEFT JOIN
        datalake_ebdb_clean.inspection AS ev
            ON turf.origin = 'Vistoria'
            AND turf.id_origin = ev.id
    WHERE 
        turf.type = 'AnaliseVistoriaSaida'
),
last_updated_task AS (
  SELECT
      id_task,
      MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated
    FROM
      datalake_crm_tasks_flows.tasks_actions_resolutions_flow
    GROUP BY 1
),
inspection_task AS (
    SELECT
        tarf.id_task,
        tarf.is_task_auto_completed
    FROM
        datalake_crm_tasks_flows.tasks_actions_resolutions_flow AS tarf
    JOIN
        last_updated_task AS lut
            ON tarf.id_task = lut.id_task
            AND DATE(CONCAT(tarf.year, '-', tarf.month, '-', tarf.day)) = lut.dt_last_updated
    WHERE
        tarf.type = 'AnaliseVistoriaSaida'
)
SELECT
    o.id_contract,
    ROW_NUMBER() OVER (PARTITION BY o.id_contract ORDER BY c.id_completed_date DESC) AS contract_rank,
    CASE 
        WHEN it.is_task_auto_completed = TRUE THEN 'Automática'
        ELSE 'Manual'
    END AS task_closed_type,
    DATEDIFF(TO_DATE(CAST(c.id_completed_date AS STRING), "yyyyMMdd"), TO_DATE(CAST(c.id_start_date AS STRING), "yyyyMMdd")) AS days_leadtime,
    TO_DATE(CAST(c.id_start_date AS STRING), "yyyyMMdd") AS dt_start_date,
    TO_DATE(CAST(c.id_completed_date AS STRING), "yyyyMMdd") AS dt_completed_date
FROM 
    datalake_offboarding.ongoing o
LEFT JOIN 
    contracts c 
        ON c.id_contract = o.id_contract 
LEFT JOIN 
    inspection_task it 
        ON it.id_task = c.id_task
WHERE 
    c.action_type <> 'CANCELED'
    AND c.id_completed_date IS NOT NULL
GROUP BY 
    1,3,4,5,6,c.id_completed_date