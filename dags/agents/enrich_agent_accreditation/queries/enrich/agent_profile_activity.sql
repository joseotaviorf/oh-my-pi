WITH agent_actions AS (
    SELECT
        ac.id_action_log,
        ac.id_agent,
        ac.id_user,
        ac.id_action,
        COALESCE(ac.agent_profile, "Not Defined") AS agent_profile,
        ac.action,
        DATEDIFF(
            COALESCE(LEAD(ac.dt_action) OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_revision), DATE('{load_end_date}')), 
            ac.dt_action
        ) AS total_active_days, 
        FIRST(ac.id_action) OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_revision DESC) IN (2, 7) AS is_currently_inactive,
        FIRST(ac.id_action_log) OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_revision DESC) = ac.id_action_log AS is_last_action_log,
        ac.ts_revision,
        ac.dt_action,
        COALESCE(LEAD(ac.dt_action) OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_revision), DATE('{load_end_date}')) AS dt_next_action
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
                    LAG(ac.agent_profile) OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_revision) <> ac.agent_profile 
                    OR LAG(ac.dt_next_action) OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_revision) <> ac.dt_action 
                THEN 1 
                ELSE 0 
            END
        ) OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_revision) AS id_group,
        ac.agent_profile,
        ac.is_currently_inactive,
        -- Here we need to rebuild this is_last_action_log column, because the filter ac.id_action NOT IN (2, 7) will eliminate the records and generate a new last record.
        FIRST(ac.id_action_log) OVER (PARTITION BY ac.id_agent ORDER BY ac.ts_revision DESC) = ac.id_action_log AS is_last_action_log,
        ac.dt_action,
        ac.dt_next_action
    FROM 
        agent_actions AS ac
    WHERE
        ac.id_action NOT IN (2, 7)
        AND (
          ac.total_active_days <> 0
          OR ac.is_last_action_log
        )
),
agent_profile_activity AS (
    SELECT
        XXHASH64(gi.id_agent, gi.agent_profile, MIN(gi.dt_action)) AS id_agent_profile_activity,
        gi.id_agent,
        gi.id_user,
        gi.id_group,
        gi.agent_profile,
        DATEDIFF(MAX(gi.dt_next_action), MIN(gi.dt_action)) AS total_active_days,
        MIN(gi.dt_action) AS dt_started,
        CASE  
            WHEN MAX(gi.is_last_action_log) IS TRUE AND MAX(gi.is_currently_inactive) IS FALSE THEN DATE('{load_end_date}')
            ELSE MAX(gi.dt_next_action)
        END AS dt_ended
    FROM 
        grouped_intervals AS gi
    GROUP BY ALL
)
SELECT 
    apa.id_agent_profile_activity,
    apa.id_agent,
    apa.id_user,
    apa.agent_profile,
    apa.total_active_days,
    apa.dt_started,
    IF(
        LEAD(apa.dt_started) OVER (PARTITION BY apa.id_agent ORDER BY apa.dt_ended) = apa.dt_ended,
        apa.dt_ended - INTERVAL 1 DAY,
        apa.dt_ended
    ) AS dt_ended
FROM 
    agent_profile_activity AS apa 
WHERE
    apa.agent_profile <> "Not Defined"
    AND apa.dt_ended BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')