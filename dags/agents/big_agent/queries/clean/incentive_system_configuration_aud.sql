SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    incentive_system,
    performance_evaluation_period,
    tier_validity_period,
    incentive_system_mod AS mod_incentive_system,
    performance_evaluation_period_mod AS mod_performance_evaluation_period,
    tier_validity_period_mod AS mod_tier_validity_period,
    classification_start_at_mod AS mod_ts_classification_started,
    classification_end_at_mod AS mod_ts_classification_ended,
    TIMESTAMP(classification_start_at) AS ts_classification_started,
    TIMESTAMP(classification_end_at) AS ts_classification_ended,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.incentive_system_configuration_aud