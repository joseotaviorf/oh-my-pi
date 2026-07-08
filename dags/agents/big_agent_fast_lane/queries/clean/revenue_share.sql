SELECT
    id,
    relation_id AS id_relation,
    invalidated_by AS id_invalidated_by,
    revenue_share_uuid AS uuid_revenue_share,
    relation_type,
    type,
    value,
    status,
    invalidation_reason,
    DATE(validity_start_at) as dt_validity_start,
    DATE(validity_end_at) as dt_validity_end,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.revenue_share
