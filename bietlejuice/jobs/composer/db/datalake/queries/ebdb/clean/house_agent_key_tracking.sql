SELECT
    id,
    agent_id AS id_agent,
    house_id AS id_house,
    comments,
    status,
    CAST(delivered_on AS DATE) AS dt_delivered,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated
FROM
    datalake_ebdb_raw.HouseAgentKeyTracking