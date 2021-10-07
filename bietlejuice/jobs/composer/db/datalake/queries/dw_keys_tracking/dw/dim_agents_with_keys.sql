SELECT
    id_house_listing AS sk_house_listing,
    COALESCE(id_agent, -1) AS sk_agent,
    id_house AS sk_house,
    all_id_agents, 
    has_keys_with_agent_attributed,
    has_keys_with_agent_delivered,
    has_keys_with_agent_returned,
    is_delivered_on_another_listing,
    is_keys_with_agent_eligible,
    is_keys_with_agent_opt_in,
    dt_attributed,
    dt_delivered,
    dt_optin,
    dt_publicated,
    dt_returned,
    NOW() AS ts_load
FROM
    datalake_ebdb_listing.agents_with_keys