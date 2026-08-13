SELECT
    id,
    tier_id AS id_tier,
    multiplication_factor,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.tier_earning_configuration