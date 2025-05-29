SELECT
    BIGINT(`id`) AS id_hub_bonus,
    business_unit_id AS id_business_unit,
    current_revision,
    agent_role,
    DATE(bonus_start_date) AS dt_bonus_start,
    DATE(bonus_end_date) AS dt_bonus_end,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.hub_bonus
