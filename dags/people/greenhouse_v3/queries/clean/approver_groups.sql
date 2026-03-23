SELECT
    -- ids
    id AS id_approver_group,
    -- Non-ids (foreign keys)
    approval_flow_id AS id_approval_flow,
    -- Non-metrics (properties)
    approvals_required,
    sort_order,
    -- Metrics (booleans)
    CAST(required_for_exception AS BOOLEAN) AS is_required_for_exception,
    -- Date, timestamp
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(resolved_at AS TIMESTAMP) AS ts_resolved,
    NOW() AS ts_load,
    -- Partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.approver_groups

