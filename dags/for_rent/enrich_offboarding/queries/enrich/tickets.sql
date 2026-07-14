WITH tickets_funnel_metrics_adjusted AS (
    SELECT
        id_contract,
        id_ticket,
        TO_DATE(ts_closed) AS dt_closed_date,
        TO_DATE(ts_closed - INTERVAL 3 HOUR) AS dt_closed_date_local,
        TO_DATE(ts_created - INTERVAL 3 HOUR) AS dt_created_date_local,
        TO_DATE(ts_initially_assigned - INTERVAL 3 HOUR) AS dt_initially_assigned_local,
        TO_DATE(ts_solved - INTERVAL 3 HOUR) AS dt_solved_date_local
    FROM
        datalake_zendesk.tickets_current
),
ticket_funnel AS (
    SELECT
        id_ticket,
        group_name,
        client_type,
        tags,
        protection_agreement,
        CASE
            WHEN group_name IN ('Rescisão - Despejo [OFF][POS][BACK]')
                AND tags NOT LIKE '%closed_by_merge%'
                AND tags NOT LIKE '%proteção_5a_cancelada%'
                AND client_type IN ('imobiliária_b2b', 'proprietário')
            THEN TRUE
            ELSE FALSE
        END AS is_property_eviction
    FROM
        datalake_zendesk.tickets_current
)
SELECT
    ong.id_contract,
    MAX(tfma.id_ticket) AS id_ticket,
    tf.group_name,
    MAX(protection_agreement) AS protection_agreement,
    DATEDIFF(MAX(tfma.dt_closed_date), MIN(tfma.dt_created_date_local)) AS lead_time_activation,
    CASE
        WHEN (ARRAY_CONTAINS(COLLECT_LIST(tf.client_type), 'imobiliária_b2b')
                OR ARRAY_CONTAINS(COLLECT_LIST(tf.client_type), 'proprietário'))
            AND (CONCAT_WS(' ',COLLECT_LIST(tf.tags)) NOT LIKE '%closed_by_merge%'
                AND CONCAT_WS(' ',COLLECT_LIST(tf.tags)) NOT LIKE '%proteção_5a_cancelada%') THEN TRUE
        ELSE FALSE
    END AS is_activation_protection,
    MAX(tf.is_property_eviction) AS is_property_eviction,
    MIN(tfma.dt_created_date_local) AS dt_created,
    MIN(tfma.dt_initially_assigned_local) AS dt_started,
    MAX(tfma.dt_solved_date_local) AS dt_solved,
    MAX(tfma.dt_closed_date) AS dt_completed,
    MAX(tfma.dt_closed_date_local) AS dt_completed_local
FROM
    datalake_offboarding.ongoing AS ong
LEFT JOIN
    tickets_funnel_metrics_adjusted tfma
        ON tfma.id_contract = ong.id_contract
LEFT JOIN
    ticket_funnel tf
        ON tfma.id_ticket = tf.id_ticket
GROUP BY
    1,3
