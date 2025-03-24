WITH agent_actions AS (
    SELECT
        ac.id_agent,
        ac.id_user,
        COALESCE(ac.business_context, "Not Defined") AS business_context,
        ac.action,
        DATEDIFF(
            COALESCE(LEAD(ac.dt_action) OVER (PARTITION BY ac.id_agent ORDER BY ac.dt_action), DATE('{load_end_date}')), 
            ac.dt_action
        ) AS total_active_days, 
        ac.is_active,
        ac.dt_action,
        COALESCE(LEAD(ac.dt_action) OVER (PARTITION BY ac.id_agent ORDER BY ac.dt_action), DATE('{load_end_date}')) AS dt_next_action
    FROM
        datalake_agent_accreditation.agent_registration_actions_log AS ac
    WHERE
        DATE(ac.dt_action) <= DATE('{load_end_date}')
),
grouped_intervals AS (
    SELECT 
        ac.id_agent,
        ac.id_user,
        SUM(
            CASE 
                WHEN 
                    LAG(ac.business_context) OVER (PARTITION BY ac.id_agent ORDER BY ac.dt_action) <> ac.business_context 
                    OR LAG(ac.dt_next_action) OVER (PARTITION BY ac.id_agent ORDER BY ac.dt_action) <> ac.dt_action 
                THEN 1 
                ELSE 0 
            END
        ) OVER (PARTITION BY ac.id_agent ORDER BY ac.dt_action) AS id_group,
        ac.business_context,
        ac.is_active,
        ac.dt_action,
        ac.dt_next_action
    FROM 
        agent_actions AS ac
    WHERE
        ac.action <> "Descredenciamento"
        AND ac.total_active_days <> 0
)
SELECT
    XXHASH64(gi.id_agent, gi.business_context, MIN(gi.dt_action)) AS id_business_context_activity,
    gi.id_agent,
    gi.id_user,
    gi.business_context,
    DATEDIFF(MAX(gi.dt_next_action), MIN(gi.dt_action)) AS total_active_days,
    MAX(gi.is_active) AS is_active,
    MIN(gi.dt_action) AS dt_started,
    MAX(gi.dt_next_action) AS dt_ended
FROM 
    grouped_intervals AS gi
WHERE
    DATE(gi.dt_next_action) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
GROUP BY 
    gi.id_agent, gi.id_user, gi.business_context, gi.id_group