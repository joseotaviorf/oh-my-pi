WITH agent_work_contract_revision AS (
    SELECT 
        awc.id,
        id_work_contract,
        LAG(id_work_contract) OVER (PARTITION BY awc.id ORDER BY rev ASC) AS id_previous_work_contract,
        revision.id_user AS id_user_change,
        rev,
        rev_type,
        is_active AS is_agent_active,
        LAG(is_active) OVER (PARTITION BY awc.id ORDER BY rev ASC) AS is_previous_active,
        CASE
            WHEN id_work_contract != LAG(id_work_contract) OVER (PARTITION BY awc.id ORDER BY rev ASC) THEN TRUE
            ELSE FALSE -- check if it's okay to attribute false for nulls
        END AS has_changed_work_contract,
        CASE
            WHEN is_active <>
                CASE
                    WHEN LAG(is_active) OVER (PARTITION BY awc.id ORDER BY rev ASC) IS NULL THEN FALSE
                    ELSE LAG(is_active) OVER (PARTITION BY awc.id ORDER BY rev ASC)
                END
            THEN TRUE
        END AS has_changed_activated,
        FROM_UNIXTIME(revision.ts_revision/1000) AS ts_revision,
        YEAR(FROM_UNIXTIME(revision.ts_revision/1000)) AS year,
        MONTH(FROM_UNIXTIME(revision.ts_revision/1000)) AS month,
        DAY(FROM_UNIXTIME(revision.ts_revision/1000)) AS day
    FROM
        datalake_ebdb_clean.agent_data_aud AS awc
    INNER JOIN
        datalake_ebdb_clean.user_revision_entity AS revision 
            ON awc.rev = revision.id
    WHERE
        DATE(FROM_UNIXTIME(revision.ts_revision/1000)) = DATE('{year}-{month}-{day}')
),
agent_work_contract_info AS (
    SELECT
        awc.id,
        awc.id_work_contract,
        awc.id_previous_work_contract,
        awc.id_user_change,
        awc.rev,
        awc.rev_type,
        cwc.contract_name AS work_contract_name,
        pwc.contract_name AS previous_work_contract_name,
        agent.name AS agent_name,
        at.types AS agent_type,
        user.name AS user_change_name,
        user.email AS user_change_email,
        CASE
            WHEN rev_type = 0 OR (has_changed_activated = TRUE AND is_previous_active != TRUE AND is_agent_active = TRUE) THEN 'ACTIVATED'
            WHEN has_changed_work_contract = TRUE AND id_work_contract = 6 THEN 'SUSPENDED'
            WHEN has_changed_work_contract = TRUE AND id_previous_work_contract = 6 THEN 'UNSUSPENDED'
            WHEN has_changed_activated = TRUE AND is_previous_active != FALSE AND is_agent_active = FALSE  THEN 'DEACTIVATED'
            WHEN has_changed_work_contract = TRUE AND id_work_contract != 6 AND id_previous_work_contract != 6 THEN 'ALTERED_CONTRACT'
        END AS action,
        awc.is_agent_active,
        awc.is_previous_active,
        awc.has_changed_work_contract,
        awc.has_changed_activated,
        awc.ts_revision,
        awc.year,
        awc.month,
        awc.day
    FROM
        agent_work_contract_revision AS awc
    LEFT JOIN
        datalake_ebdb_clean.user AS user 
            ON awc.id_user_change = user.id
    LEFT JOIN
        datalake_ebdb_clean.user AS agent 
            ON awc.id = agent.id_agent
    LEFT JOIN
        datalake_ebdb_clean.work_contract AS cwc 
            ON awc.id_work_contract = cwc.id
    LEFT JOIN
        datalake_ebdb_clean.work_contract AS pwc 
            ON awc.id_previous_work_contract = pwc.id
    LEFT JOIN
        datalake_ebdb_clean.agent_data_types AS at 
            ON at.id_agent_data = agent.id_agent
    WHERE
        has_changed_work_contract = TRUE OR has_changed_activated = TRUE
)
SELECT
    id AS id_agent,
    id_work_contract,
    id_previous_work_contract,
    id_user_change,
    rev,
    rev_type,
    work_contract_name,
    previous_work_contract_name,
    agent_name,
    agent_type,
    user_change_name,
    user_change_email,
    CASE
        WHEN action = 'ACTIVATED' THEN
            CASE
                WHEN LAG(rev) OVER (PARTITION BY id, action ORDER BY rev ASC) IS NOT NULL THEN 'REACTIVATED'
                ELSE 'ACTIVATED' END
        ELSE action
    END AS action,
    is_agent_active,
    has_changed_work_contract,
    has_changed_activated,
    ts_revision,
    year,
    month,
    day
FROM
    agent_work_contract_info