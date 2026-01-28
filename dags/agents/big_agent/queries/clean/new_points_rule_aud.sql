SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    score_rule_id AS id_score_rule,
    operation,
    trigger,
    points,
    max_points,
    score_rule_id_mod AS mod_id_score_rule,
    operation_mod AS mod_operation,
    trigger_mod AS mod_trigger,
    points_mod AS mod_points,
    max_points_mod AS mod_max_points,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.new_points_rule_aud