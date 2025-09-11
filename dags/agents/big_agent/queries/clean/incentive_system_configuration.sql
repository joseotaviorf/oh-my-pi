SELECT
    id,
    incentive_system,
    performance_evaluation_period,
    tier_validity_period,
    TIMESTAMP(classification_start_at) AS ts_classification_start,
    TIMESTAMP(classification_end_at) AS ts_classification_end,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.incentive_system_configuration