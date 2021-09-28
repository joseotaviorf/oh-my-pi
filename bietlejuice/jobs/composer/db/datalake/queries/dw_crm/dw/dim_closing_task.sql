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
  NOW() AS ts_load,
  year,
  month,
  day
FROM 
  datalake_crm_tasks_history_flows.tasks_history_resolutions_flow
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
  AND year = {year}
  AND month = {month}
  AND day = {day}