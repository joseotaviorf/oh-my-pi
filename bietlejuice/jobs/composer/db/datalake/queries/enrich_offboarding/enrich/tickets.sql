WITH tickets_funnel_metrics_adjusted AS (
    SELECT
        tfm.id_contract,
        tfm.id_ticket,
        TO_DATE(tfm.ts_closed) AS dt_closed_date,
        TO_DATE(tfm.ts_created_local) AS dt_created_date_local,
        TO_DATE(tfm.ts_initially_assigned_local) AS dt_initially_assigned_local,
        TO_DATE(tfm.ts_solved_local) AS dt_solved_date_local
    FROM
        datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
)
SELECT
    ong.id_contract,
    MAX(tfma.id_ticket) as id_ticket,
    tf.group_name,
    DATEDIFF(MAX(tfma.dt_closed_date), MIN(tfma.dt_created_date_local)) AS lead_time_activation,
    CASE
        WHEN (ARRAY_CONTAINS(COLLECT_LIST(tf.client_type), 'imobiliária_b2b')
                OR ARRAY_CONTAINS(COLLECT_LIST(tf.client_type), 'proprietário'))
            AND (CONCAT_WS(' ',COLLECT_LIST(tf.tags)) NOT LIKE '%closed_by_merge%' 
                AND CONCAT_WS(' ',COLLECT_LIST(tf.tags)) NOT LIKE '%proteção_5a_cancelada%') THEN TRUE
        ELSE FALSE
    END AS is_activation_protection,
    MIN(tfma.dt_created_date_local) AS dt_created_budgeting,
    MIN(tfma.dt_initially_assigned_local) AS dt_started_budgeting,
    MAX(tfma.dt_solved_date_local) AS dt_solved_budgeting,
    MAX(tfma.dt_closed_date) AS dt_completed_budgeting
FROM 
    datalake_offboarding.ongoing AS ong 
LEFT JOIN
    tickets_funnel_metrics_adjusted tfma 
        ON tfma.id_contract = ong.id_contract
LEFT JOIN
    datalake_zendesk_ticket_funnels.ticket_funnel tf 
        ON tfma.id_ticket = tf.id_ticket
GROUP BY 
    1,3
