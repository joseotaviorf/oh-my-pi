SELECT
    id,
    earning_source_id AS id_earning_source,
    revenue_share_id AS id_revenue_share,
    external_receiver_id AS id_external_receiver,
    earning_uuid AS uuid_earning,
    external_receiver_type,
    incentive_system,
    calculated_from,
    currency,
    status,
    reason,
    author,
    revenue_amount,
    revenue_percentage,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.new_earnings