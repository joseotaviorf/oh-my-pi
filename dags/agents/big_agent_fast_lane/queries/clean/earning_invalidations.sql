SELECT
    id,
    earning_id AS id_earning,
    replaced_by AS id_replaced_by,
    author,
    reason,
    description,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.earning_invalidations