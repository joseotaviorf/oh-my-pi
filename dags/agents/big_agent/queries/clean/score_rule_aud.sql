SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    min_score,
    min_score_mod AS mod_min_score,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.score_rule_aud