SELECT
    `id` AS id_brokerage_fee_baseline,
    negotiation_type,
    agent_role,
    current_revision,
    DATE (bonus_start_date) AS dt_bonus_start,
    DATE (bonus_end_date) AS dt_bonus_end,
    created_at AS ts_created
FROM
    datalake_nazare_job_cluster_raw.brokerage_fee_baseline
