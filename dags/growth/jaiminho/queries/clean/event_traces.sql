SELECT
    CAST(id AS BIGINT) AS id,
    CAST(traceId AS BIGINT) AS id_trace,
    CAST(entityId AS BIGINT) AS id_entity,
    entityName AS entity_name,
    destination,
    status,
    channel,
    errorName AS error_name,
    errorInfo AS error_info,
    isError AS is_error,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    YEAR(updatedAt) AS year,
    MONTH(updatedAt) AS month,
    DAY(updatedAt) AS day
FROM datalake_jaiminho_raw.event_traces
