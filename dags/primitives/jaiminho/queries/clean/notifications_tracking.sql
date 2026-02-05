SELECT
  CAST(id AS BIGINT) AS id,
  notificationId AS id_notification,
  status as state,
  errorInfo AS error_info,
  errorCode AS error_code,
  CAST(timestamp AS TIMESTAMP) AS ts_sent,
  CAST(createdAt AS TIMESTAMP) AS ts_created,
  messageUid AS message_uid
FROM
  datalake_jaiminho_raw.notifications_tracking
