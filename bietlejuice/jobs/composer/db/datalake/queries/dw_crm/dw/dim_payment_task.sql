-- TO DO: After finishing CRM migration, it is necessary to rename columns following our Naming Conventions
SELECT
    tf.id_task AS sk_task,
    tf.score_factor,
    tf.version,
    tf.origin,
    tf.type,
    tf.description,
    tf.subject,
    CAST(titles AS STRING) AS titles,
    CAST(workgroups AS STRING) AS workgroups,
    ac.status AS tenant_refund_status,
    tf.hours_task_started_to_completed AS hours_task_start_to_completed,
    tf.is_resolved AS flg_solved,
    tf.is_task_auto_completed,
    tf.ts_started AS ts_start,
    tf.ts_completed,
    tf.ts_silenced_until,
    NOW() AS ts_load,
    tf.year,
    tf.month,
    tf.day
FROM
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow AS tf
JOIN
    datalake_crm.tasks AS tk
        ON tf.id_task = tk.id
        AND DATE(CONCAT(tf.year, '-', tf.month, '-', tf.day)) = DATE(CONCAT(tk.year, '-', tk.month, '-', tk.day))
LEFT JOIN
    datalake_heimdall_clean.activity AS ac
        ON ac.id = tk.id_state
WHERE
    (tf.type IN (
        'AceiteDaAntecipacaoAluguel',
        'BuscarPrimeiroBoleto',
        'ConfirmarBoletoCondominio',
        'PedidoDeReembolso',
        'PedidoDeReembolsoInquilino',
        'PedidoDeReembolsoInquilinoCondominio'
        )
        OR (tf.type = 'Manual' 
                AND tf.id_workgroup IN (
                    'DEP_ACORDOS_DESCONTOS_ID',
                    'DEP_FINANCEIRO_ID',
                    'DEP_ID_FINANCEIRO_PAYMENTS',
                    'DEP_ID_PAYMENTS_PROJECTS',
                    'DEP_OFFBOARDING_FINANCEIRO',
                    'DEP_ONBOARDING_FINANCEIRO',
                    'DEP_PAYMENTS_SELFCONDO'
                )
        )
    )
    AND tf.year = {year}
    AND tf.month = {month}
    AND tf.day = {day}