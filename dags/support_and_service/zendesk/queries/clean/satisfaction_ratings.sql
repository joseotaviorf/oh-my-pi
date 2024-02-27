SELECT
  id AS id_satisfaction_rating,
  ticket_id AS id_ticket,
  reason_id AS id_reason,
  group_id AS id_group,
  assignee_id AS id_assignee,
  requester_id AS id_requester,
  score,
  url
  reason,
  dt AS dt_extracted,
  created_at AS ts_created,
  updated_at AS ts_updated,
  NOW() AS ts_load,
  YEAR(dt) AS year,
  MONTH(dt) AS month,
  DAY(dt) AS day
FROM
  datalake_zendesk_tickets_raw.satisfaction_ratings
WHERE
  dt IN (CAST('{year}-{month}-{day}' AS DATE), CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY)
