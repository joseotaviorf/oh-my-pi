WITH last_updated_task AS (
    SELECT DISTINCT
      id,
      LAST_VALUE(id_origin) OVER(PARTITION BY id ORDER BY DATE(CONCAT(year, '-', month, '-', day)) ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS id_origin,
      MAX(DATE(CONCAT(year, '-', month, '-', day))) OVER (PARTITION BY id) AS dt_last_updated
    FROM
      datalake_crm.tasks
)
SELECT DISTINCT
    tf.id_task AS sk_task,
    ac.id AS sk_activity,
    ac.type AS type_activity,
    tf.score_factor,
    tf.version,
    tf.origin,
    tf.type,
    tf.description,
    tf.subject,
    CAST(tf.titles AS STRING) AS titles,
    CAST(tf.workgroups AS STRING) AS workgroups,
    ac.status AS tenant_refund_status,
    tf.hours_task_started_to_completed AS hours_task_start_to_completed,
    tf.is_resolved AS flg_solved,
    tf.is_task_auto_completed,
    tf.ts_started AS ts_start,
    tf.ts_completed,
    tf.ts_silenced_until,
    NOW() AS ts_load
FROM
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow AS tf
INNER JOIN
    last_updated_task AS lut
        ON tf.id_task = lut.id
        AND DATE(CONCAT(tf.year, '-', tf.month, '-', tf.day)) = lut.dt_last_updated
LEFT JOIN
    datalake_heimdall.activity AS ac
        ON ac.id = lut.id_origin
WHERE
    (tf.type IN (
        'BuscarPrimeiroBoleto',
        'PedidoDeReembolso',
        'ConfirmarBoletoCondominio',
        'PedidoDeReembolsoInquilino',
        'PedidoDeReembolsoInquilinoReparoPagamento',
        'PedidoDeReembolsoInquilinoCondominio',
        'PedidoDeReembolsoInquilinoReparo',
        'PedidoDeReembolsoProprietarioCondominio',
        'AceiteDaAntecipacaoAluguel'
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
