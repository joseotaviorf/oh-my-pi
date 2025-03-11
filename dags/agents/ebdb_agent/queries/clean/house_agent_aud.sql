SELECT
    id,
    agent_id AS id_agent,
    house_id AS id_house,
    REV AS rev,
    CAST(REVTYPE AS SMALLINT) AS rev_type,
    business_context,
    relation_type,
    agent_has_keys AS has_house_keys,
    business_context_MOD AS mod_business_context,
    relation_type_MOD AS mod_relation_type,
    agent_has_keys_MOD AS mod_has_house_keys,
    start_at_MOD AS mod_ts_started,
    end_at_MOD AS mod_ts_ended,
    start_at AS ts_started,
    end_at AS ts_ended
FROM
    datalake_ebdb_raw.houseagent_aud