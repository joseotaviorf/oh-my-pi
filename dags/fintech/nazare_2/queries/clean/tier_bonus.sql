SELECT
    `id` AS id_tier_bonus,
    agent_id AS id_agent,
    agent_role,
    current_revision,
    DATE(bonus_start_date) AS dt_bonus_start,
    DATE(bonus_end_date) AS dt_bonus_end,
    created_at AS ts_created
FROM
    datalake_nazare_raw.tier_bonus
