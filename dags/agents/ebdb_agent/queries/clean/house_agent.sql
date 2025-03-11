SELECT
    id,
    agent_id AS id_agent,
    house_id AS id_house,
    business_context,
    relation_type,
    when_agent_got_key,
    agent_has_keys AS has_house_keys,
    returnkeyuntil AS ts_key_returned,
    start_at AS ts_started,
    end_at AS ts_ended,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.houseagent