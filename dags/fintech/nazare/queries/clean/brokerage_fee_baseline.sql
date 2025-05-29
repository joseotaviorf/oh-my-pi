SELECT
    BIGINT(`id`) AS id_brokerage_fee_baseline,
    negotiation_type,
    agent_role,
    current_revision,
    DATE(bonus_start_date) AS dt_bonus_start,
    DATE(bonus_end_date) AS dt_bonus_end,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.brokerage_fee_baseline
