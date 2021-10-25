WITH last_updated_task AS (
  SELECT
      id,
      MAX(DATE(CONCAT(year, '-', month, '-', day))) AS dt_last_updated
    FROM
      datalake_crm.tasks
    GROUP BY 1
)
SELECT
  id_task AS sk_task,
  score_factor,
  hours_task_start_to_completed,
  version,
  origin,
  CAST(titles AS STRING),
  CAST(workgroups AS STRING),
  type,
  description,
  subject,
  is_resolved AS flg_solved,
  is_task_auto_completed,
  ts_start,
  ts_completed,
  ts_silenced_until,
  NOW() AS ts_load
FROM 
  datalake_crm_tasks_history_flows.tasks_history_resolutions_flow AS thf
JOIN
    last_updated_task AS lut
        ON thf.id_task = lut.id
        AND DATE(CONCAT(thf.year, '-', thf.month, '-', thf.day)) = lut.dt_last_updated
WHERE
  (
      type IN (
        'FrontEnd', 
        'CriarMinuta',
        'AprovarMinuta',
        'FollowUpAssinaturas',
        'EnviarContratoViaEmail',
        'AnalisarDocumentacaoProprietario',
        'AlinhamentoComPP',
        'VerificacaoComIQ'
    ) 
    OR (
        type = 'Manual' 
        AND id_workgroup IN ('DEP_CLOSING_ID')
    )
  )