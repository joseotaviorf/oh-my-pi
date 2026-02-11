SELECT
    id,
    code,
    name,
    metadata,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    TIMESTAMP(disabled_at) AS ts_disabled
FROM
    datalake_payout_system_raw.requester
