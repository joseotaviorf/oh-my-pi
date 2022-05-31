WITH tickets_funnel_metrics_adjusted AS (
    WITH tenant AS (
        SELECT DISTINCT
            tmc_t.id_ticket,
            ch_t.id_contract AS id_contract,
            -- tickets will only have a valid client key according to its corresponding client type
            CASE
                WHEN tmc_t.client_type = 'inquilino' THEN ch_t.id_client
            END AS id_client
        FROM
            datalake_zendesk_tickets.ticket_measurements tmc_t
        LEFT JOIN
            datalake_ebdb_contract.contract_house ch_t
                ON tmc_t.id_contract = ch_t.id_contract
    )
    SELECT
        ten.id_contract,
        tfm.id_ticket,
        TO_DATE(tfm.ts_closed) AS dt_closed_date,
        TO_DATE(tfm.ts_created_local) AS dt_created_date_local,
        TO_DATE(tfm.ts_initially_assigned_local) AS dt_initially_assigned_local,
        TO_DATE(tfm.ts_solved_local) AS dt_solved_date_local
    FROM
        datalake_zendesk_ticket_funnels.tickets_funnel_metrics tfm
    LEFT JOIN
        tenant ten
            ON tfm.id_ticket = ten.id_ticket
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
    MIN(tfma.dt_created_date_local) AS dt_created,
    MIN(tfma.dt_initially_assigned_local) AS dt_started,
    MAX(tfma.dt_solved_date_local) AS dt_solved,
    MAX(tfma.dt_closed_date) AS dt_completed
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
