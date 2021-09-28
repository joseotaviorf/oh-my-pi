-- TO DO: After finishing CRM migration, it is necessary to rename columns following our Naming Conventions
SELECT
    id_task AS sk_task,
    score_factor,
    version,
    origin,
    type,
    description,
    subject,
    CAST(titles AS STRING) AS titles,
    CAST(workgroups AS STRING) AS workgroups,
    hours_task_started_to_completed AS hours_task_start_to_completed,
    is_resolved AS flg_solved,
    is_task_auto_completed,
    ts_started AS ts_start,
    ts_completed,
    ts_silenced_until,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow
WHERE
    (type IN (
        'DataDeRescisaoAlterada',
        'EncerrarContrato',
        'FollowUpReparosRescisao',
        'OrientarInquilinoDesocupacao',
        'OrientarInquilinoRescisao',
        'OrientarProprietarioRescisao',
        'ProtecaoReparosRescisao',
        'RescisaoCancelada',
        'RescisaoPreVigencia',
        'RevisarCancelamentoDeRescisao',
        'RevisarPagamentosRescisao',
        'VerificarDesocupacaoImovel'
        )
        OR (id_workgroup IN (
            'DEP_OFFBOARDING_2',
            'DEP_OFFBOARDING_ID',
            'DEP_OFFBOARDING_WORKFLOW_ID',
            'DEP_OFFBOARDING_WORKFLOW_STEP_ONE_ID',
            'DEP_OFFBOARDING_WORKFLOW_STEP_TWO_ID',
            'DEP_OFFBOARDING_WORKFLOW_STEP_THREE_ID'
            )
            AND type = 'Manual')
    )
    AND year = {year}
    AND month = {month}
    AND day = {day}