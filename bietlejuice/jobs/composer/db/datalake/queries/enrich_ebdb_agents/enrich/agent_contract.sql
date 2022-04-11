WITH agent_contract AS (
    SELECT
        aud.id AS id_agent,
        u.id AS id_user_agent,
        aud.id_work_contract,
        ct.contract_name AS work_contract_name,
        ROW_NUMBER() OVER (PARTITION BY aud.id ORDER BY ure.ts_revision DESC) AS r,
        CAST(FROM_UNIXTIME(ure.ts_revision / 1000) AS TIMESTAMP) AS ts_work_contract_started
    FROM
        datalake_ebdb_clean.agent_data_aud AS aud
    JOIN 
        datalake_ebdb_clean.user_revision_entity AS ure 
        ON aud.REV = ure.id
    LEFT JOIN 
        datalake_ebdb_clean.user AS u
            ON u.id_agent = aud.id
    LEFT JOIN
        datalake_ebdb_clean.work_contract AS ct 
            ON aud.id_work_contract = ct.id 
),
current_contract AS (
    SELECT
        id_agent,
        id_work_contract,
        work_contract_name
    FROM
        agent_contract
    WHERE
        r = 1
),
base_agents AS (
    SELECT
        ac.*,
        LAG(ac.id_work_contract) OVER(PARTITION BY ac.id_agent ORDER BY ac.r DESC) AS id_previous_work_contract,
        LAG(ac.work_contract_name) OVER(PARTITION BY ac.id_agent ORDER BY ac.r DESC) AS previous_work_contract_name,
        cc.id_work_contract AS id_current_work_contract,
        cc.work_contract_name AS current_work_contract_name
    FROM
        agent_contract AS ac
    LEFT JOIN
        current_contract AS cc
            ON cc.id_agent = ac.id_agent
)
SELECT
    id_agent,
    id_user_agent,
    id_previous_work_contract,
    id_work_contract,
    id_current_work_contract,
    previous_work_contract_name,
    work_contract_name,
    current_work_contract_name,
    ts_work_contract_started,
    LEAD(ts_work_contract_started) OVER(PARTITION BY id_agent ORDER BY r DESC) AS ts_work_contract_ended
FROM
    base_agents
WHERE
    previous_work_contract_name IS DISTINCT FROM work_contract_name
