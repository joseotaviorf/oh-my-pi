SELECT
  CAST(id_ticket AS BIGINT) AS sk_ticket,
  CAST(COALESCE(id_problem_ticket, -1) AS BIGINT) AS sk_problem_ticket,
  status,
  type,
  tags,
  via_channel AS ticket_via,
  group_name,
  channel,
  priority,
  recipient,
  TO_JSON(custom_fields) AS custom_fields,
  subject,
  description,
  BOOLEAN(is_public) AS has_public_comments,
  ts_created,
  ts_created - INTERVAL 3 HOUR AS ts_created_brt,
  ts_updated,
  ts_updated - INTERVAL 3 HOUR AS ts_updated_brt,
  NOW() AS ts_load
FROM
  datalake_zendesk.tickets_current
