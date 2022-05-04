WITH raw AS (
    SELECT 
        id,
        id_work_contract AS workcontract_id,
        LAG(id_work_contract) OVER (PARTITION BY id ORDER BY rev ASC) AS previous_workcontract_id,
        is_active AS ativo,
        LAG(is_active) OVER (PARTITION BY id ORDER BY rev ASC) AS previous_ativo,
        CASE
            WHEN id_work_contract != LAG(id_work_contract) OVER (PARTITION BY id ORDER BY rev ASC) THEN TRUE
        END AS changed_workcontract,
        CASE
            WHEN is_active <>
                CASE
                    WHEN LAG(is_active) OVER (PARTITION BY id ORDER BY rev ASC) IS NULL THEN FALSE
                        ELSE LAG(is_active) OVER (PARTITION BY id ORDER BY rev ASC)
                END THEN TRUE
        END AS changed_activated,
        rev,
        rev_type AS revtype
    FROM
        datalake_ebdb_clean.agent_data_aud
),
base AS (
    SELECT
        raw.*,
        revision.id_user AS user_change_id,
        cwc.contract_name AS workcontract_name,
        pwc.contract_name AS previous_workcontract_name,
        agent.name AS agent_name,
        at.types AS agent_type,
        user.name AS user_change_name,
        user.email AS user_change_email,
        TIMESTAMP(FROM_UNIXTIME(revision.ts_revision/1000)) AS date,
        CASE
            WHEN REVTYPE=0 OR (changed_activated = TRUE AND previous_ativo != TRUE AND ativo = TRUE) THEN 'ACTIVATED'
            WHEN changed_workcontract = TRUE AND workcontract_id=6 THEN 'SUSPENDED'
            WHEN changed_workcontract = true AND previous_workcontract_id=6 THEN 'UNSUSPENDED'
            WHEN changed_activated = TRUE AND previous_ativo != FALSE AND ativo = FALSE  THEN 'DEACTIVATED'
            WHEN changed_workcontract = TRUE AND workcontract_id!=6 AND previous_workcontract_id!=6 THEN 'ALTERED_CONTRACT'
        END AS action
    FROM
        raw
    INNER JOIN
        datalake_ebdb_clean.user_revision_entity revision 
            ON raw.rev=revision.id
    LEFT JOIN
        datalake_ebdb_clean.user user 
            ON revision.id_user=user.id
    LEFT JOIN
        datalake_ebdb_clean.user agent 
            ON raw.id=agent.id_agent
    LEFT JOIN
        datalake_ebdb_clean.work_contract cwc 
            ON raw.workcontract_id=cwc.id
    LEFT JOIN
        datalake_ebdb_clean.work_contract pwc 
            ON raw.previous_workcontract_id=pwc.id
    LEFT JOIN
        datalake_ebdb_clean.agent_data_types at 
            ON at.id_agent_data = agent.id_agent
    WHERE
        (changed_workcontract = TRUE) OR changed_activated=true
),
base_clean AS (
    SELECT
        id AS agent_id,
        workcontract_id,
        previous_workcontract_id,
        user_change_id,
        rev,
        CASE
            WHEN action = 'ACTIVATED' THEN
                CASE
                    WHEN LAG(rev) OVER (PARTITION BY id, action ORDER BY rev ASC) IS NOT NULL THEN 'REACTIVATED'
                    ELSE 'ACTIVATED' END
            ELSE action
        END AS action,
        ativo AS agent_active,
        agent_name,
        agent_type,
        workcontract_name,
        changed_activated,
        changed_workcontract,
        previous_workcontract_name,
        user_change_name,
        user_change_email,
        date,
        NOW() AS ts_load
    FROM
        base
)
SELECT 
    *
FROM
    base_clean
ORDER BY rev ASC
