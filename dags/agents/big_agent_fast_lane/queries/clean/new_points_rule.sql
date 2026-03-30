SELECT
    id,
    score_rule_id AS id_score_rule,
    operation,
    trigger,
    points,
    max_points,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.new_points_rule