WITH ticket_history_base AS (
    SELECT
        *
    FROM
        datalake_zendesk_tickets_clean.tickets_history
    WHERE
        YEAR(ts_updated) >= YEAR(CURRENT_DATE()) - 1
),
contestation_date AS (
    SELECT
        id_ticket,
        MIN(ts_updated) AS ts_contestation
    FROM 
        ticket_history_base
    WHERE
        tags LIKE ANY (
          "%pp_autosserviço_contestou%", "%iq_pp_autosserviço_contestou%", "%alteração_de_responsabilidade_criticidade%", 
          "%acompanhamento_alteracao_responsabilidade_criticidade%", "%check_responsabilidade_reparos%", "%pp_autosserviço_contestou%"
        )
    GROUP BY 1
),
resolution_contestation_date AS (
    SELECT
        id_ticket,
        MIN(ts_updated) AS ts_resolution_contestation
    FROM 
        ticket_history_base
    WHERE
        tags LIKE ANY (
          "%macro_ro_cont_benfeitoria_pp%", "%macro_ro_cont_benfeitoria_iq%", "%macro_ro_cont_terceiros_pp%", 
          "%macro_ro_cont_terceiros_iq%", "%macro_ro_cont_aprovada_iq%", "%macro_ro_cont_aprovada_pp%",
          "%macro_ro_cont_reprovada_pp%", "%macro_ro_cont_reprovada_iq%", "%closed_by_merge%",
          "%reprovado_ro_%", "%aprovado_ro_%", "%opcional_ro_%", "%ação_backlog_contestação%",
          "%alteração_reprovada%", "%alteração_aprovada%", "%alteração_benfeitoria%"
        )
    GROUP BY 1
),
repair_tickets AS (        
    SELECT DISTINCT 
        tf.id_ticket,
        CASE 
          WHEN (tf.tags LIKE ANY ('%iq_pp_autosserviço_contestou%', '%pp_autosserviço_contestou%')) THEN 'PWA'
          WHEN (tf.tags LIKE ANY (
              '%alteração_de_responsabilidade_criticidade%', '%acompanhamento_alteracao_responsabilidade_criticidade%', 
              '%check_responsabilidade_reparos%', '%pp_contestou%'
            )
          ) AND tf.tags NOT LIKE '%ticket_acompanhamento%' THEN 'CX'
        END AS contestation_task_origin, 
        IF(tf.tags LIKE '%closed_by_merge%', TRUE, FALSE) AS is_closed_by_merge,
        IF(ww.dt_end_1 > (CURRENT_DATE - INTERVAL 1 DAY) AND ts_resolution_contestation IS NULL AND DATE(tfm.ts_solved_local) IS NULL, TRUE, FALSE) AS is_contestation_backlog,
        IF(tf.tags LIKE '%ticket_acompanhamento%', TRUE, FALSE) AS is_ticket_followup,
        cd.ts_contestation,
        rc.ts_resolution_contestation
    FROM 
        datalake_zendesk_ticket_funnels.ticket_funnel AS tf
    LEFT JOIN
        datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
            ON tf.id_ticket = tfm.id_ticket
    LEFT JOIN 
        contestation_date AS cd 
            ON cd.id_ticket = tf.id_ticket
    LEFT JOIN 
        resolution_contestation_date AS rc 
            on rc.id_ticket = tf.id_ticket
    LEFT JOIN 
        datalake_date.workday_window AS ww 
            ON ww.dt_Ref = DATE(cd.contestation_date) AND id_city = 39
    WHERE 
        tf.group_name IN ('FullService [Back]','Prestadores Parceiros [SO]','Reparos [BACK]','Triagem Reparos [Back]','FullService [BACK]')
        AND (DATE(tfm.ts_solved_local) >= DATE('2023-06-01') OR tfm.ts_solved_local IS NULL)
        AND tf.channel NOT IN ('call')
        AND tf.status NOT IN ('deleted')
        AND tf.tags NOT LIKE '%caso_ticket_agregador%'
)
SELECT DISTINCT 
    id_ticket,
    contestation_task_origin,
    is_closed_by_merge,
    is_contestation_backlog,
    is_ticket_followup,
    ts_contestation,
    ts_resolution_contestation
FROM 
    repair_tickets
