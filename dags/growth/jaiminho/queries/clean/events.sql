SELECT
    CAST(id AS BIGINT) AS id,
    CAST(userId AS BIGINT) AS id_user,
    callbackId AS id_callback,
    referenceName AS reference_name,
    referenceId AS reference_id,
    type,
    status,
    callbackChannel AS callback_channel,
    callbackTrigger AS callback_trigger,
    tracingContext AS tracing_context,
    extraInfo AS extra_info,
    version,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    YEAR(updatedAt) AS year,
    MONTH(updatedAt) AS month,
    DAY(updatedAt) AS day
FROM datalake_jaiminho_raw.events
