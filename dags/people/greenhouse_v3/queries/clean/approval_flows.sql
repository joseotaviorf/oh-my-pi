SELECT
    -- ids
    id AS id_approval_flow,
    -- Non-ids (foreign keys)
    job_id AS id_job,
    offer_id AS id_offer,
    requested_by_id AS id_requested_by,
    -- Non-metrics (properties)
    approval_type,
    approval_status,
    version,
    -- Metrics (booleans)
    CAST(sequential AS BOOLEAN) AS is_sequential,
    -- Date, timestamp
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- Partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.approval_flows

