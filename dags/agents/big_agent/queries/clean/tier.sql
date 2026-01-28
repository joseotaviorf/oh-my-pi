SELECT
    id,
    incentive_engine_id AS id_incentive_engine,
    classifier_id AS id_classifier,
    qualifier_id AS id_qualifier,
    name,
    priority,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.tier