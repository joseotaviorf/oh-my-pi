SELECT
    `id` AS id_associate_executive_bonus,
    agent_id AS id_agent,
    business_unit_id AS id_business_unit,
    current_revision,
    DATE(bonus_start_date) AS dt_bonus_start,
    DATE(bonus_end_date) AS dt_bonus_end,
    created_at AS ts_created
FROM
    datalake_nazare_raw.associate_executive_bonus
