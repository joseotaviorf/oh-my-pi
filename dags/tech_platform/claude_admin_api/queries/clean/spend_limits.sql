-- Bootstrap clean table for Data Contracts (schema creation).
-- Pass through the api_ingestion raw contract only (payload + load partitions).
-- SELECT * is rejected by validate-lineage-consistency.
SELECT
    payload,
    ts_load,
    year,
    month,
    day
FROM
    datalake_claude_usage_raw.spend_limits
