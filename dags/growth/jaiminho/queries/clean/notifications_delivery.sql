SELECT
    CAST(id AS BIGINT) AS id,
    CAST(notificationId AS BIGINT) AS id_notification,
    messageUid AS uid_message,
    status,
    dispatcher,
    tracingContext AS tracing_context,
    result,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    YEAR(updatedAt) AS year,
    MONTH(updatedAt) AS month,
    DAY(updatedAt) AS day
FROM datalake_jaiminho_raw.notifications_delivery
