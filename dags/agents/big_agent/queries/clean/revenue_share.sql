SELECT
    id,
    relation_id AS id_relation,
    invalidated_by AS id_invalidated_by,
    revenue_share_uuid AS uuid_revenue_share,
    relation_type,
    condition_type,
    value,
    status,
    invalidation_reason,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.revenue_share