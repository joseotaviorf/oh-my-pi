SELECT
    id,
    agent_id AS id_agent,
    house_id AS id_house,
    rev,
    revtype AS rev_type,
    comments,
    status,
    agent_id_mod AS mod_id_agent,
    comments_mod AS mod_comments,
    status_mod AS mod_status,
    delivered_on_mod AS mod_dt_delivered,
    CAST(delivered_on AS DATE) AS dt_delivered
FROM
    datalake_ebdb_test_raw.HouseAgentKeyTracking_aud