SELECT
    BIGINT(`id`) AS id_associate_executive_bonus,
    BIGINT(agent_id) AS id_agent,
    BIGINT(business_unit_id) AS id_business_unit,
    current_revision,
    DATE(bonus_start_date) AS dt_bonus_start,
    DATE(bonus_end_date) AS dt_bonus_end,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.associate_executive_bonus
