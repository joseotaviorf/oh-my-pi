SELECT
    id,
    revenue_share_id AS id_revenue_share,
    replaced_by AS id_replaced_by,
    author,
    reason,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.revenue_share_invalidations
