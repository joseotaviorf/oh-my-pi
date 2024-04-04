SELECT DISTINCT
  id AS id_satisfaction_rating,
  ticket_id AS id_ticket,
  reason_id AS id_reason,
  group_id AS id_group,
  assignee_id AS id_assignee,
  requester_id AS id_requester,
  score,
  url
  reason,
  CAST(dt AS DATE) AS dt_extracted,
  CAST(created_at AS TIMESTAMP) AS ts_created,
  CAST(updated_at AS TIMESTAMP) AS ts_updated,
  NOW() AS ts_load,
  YEAR(CAST(dt AS DATE)) AS year,
  MONTH(CAST(dt AS DATE)) AS month,
  DAY(CAST(dt AS DATE)) AS day
FROM
  datalake_zendesk_raw.satisfaction_ratings
WHERE
  dt IN (MAKE_DATE({year}, {month}, {day}), MAKE_DATE({year}, {month}, {day}) + INTERVAL 1 DAY)
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_satisfaction_rating, ts_updated ORDER BY dt_extracted DESC) = 1
