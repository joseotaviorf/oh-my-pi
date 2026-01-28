SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    incentive_engine_id AS id_incentive_engine,
    classifier_id AS id_classifier,
    qualifier_id AS id_qualifier,
    name,
    priority,
    incentive_engine_id_mod AS mod_id_incentive_engine,
    classifier_id_mod AS mod_id_classifier,
    qualifier_id_mod AS mod_id_qualifier,
    name_mod AS mod_name,
    priority_mod AS mod_priority,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.tier_aud