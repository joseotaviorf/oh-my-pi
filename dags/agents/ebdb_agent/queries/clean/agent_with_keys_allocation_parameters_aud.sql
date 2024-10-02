SELECT
    id,
    rev,
    revtype AS rev_type,
    agent_id AS id_agent,
    agent_id_MOD AS mod_id_agent,
    total_houses,
    total_houses_MOD AS mod_total_houses,
    capacity,
    capacity_MOD AS mod_capacity,
    average_ticket,
    average_ticket_MOD AS mod_average_ticket,
    average_lat,
    average_lat_MOD AS mod_average_lat,
    average_lng,
    average_lng_MOD AS mod_average_lng,
    CAST(has_opted_out AS BOOLEAN) AS has_opted_out,
    has_opted_out_MOD AS mod_has_opted_out
FROM 
    datalake_ebdb_raw.AgentWithKeysAllocationParameters_AUD