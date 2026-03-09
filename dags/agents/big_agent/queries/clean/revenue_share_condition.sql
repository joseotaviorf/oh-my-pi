SELECT
    id,
    revenue_share_id AS id_revenue_share,
    condition_type,
    value,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.revenue_share_condition
