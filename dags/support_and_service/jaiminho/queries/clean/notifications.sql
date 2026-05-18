SELECT
  CAST(id AS BIGINT) AS id,
  CAST(eventId AS BIGINT) AS id_event,
  CAST(userId AS BIGINT) AS id_user,
  CAST(retry AS INT) AS retry,
  action,
  status,
  channel,
  tags,
  profile,
  scope,
  COALESCE(templateName, payload:bodyTemplate) AS template,
  errorCode AS error_code,
  errorInfo AS error_info,
  state,
  payload,
  CAST(sentAt AS TIMESTAMP) AS ts_sent,
  CAST(createdAt AS TIMESTAMP) AS ts_created,
  YEAR(updatedAt) AS year,
  YEAR(updatedAt) AS month,
  YEAR(updatedAt) AS day
FROM
  datalake_jaiminho_raw.notifications
