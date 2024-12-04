SELECT
  CAST(id_ticket AS BIGINT) AS sk_ticket,
  CAST(COALESCE(id_problem_ticket, -1) AS BIGINT) AS sk_problem_ticket,
  COALESCE(CAST(id_contract AS BIGINT), -1) AS sk_contract,
  MD5(
    CONCAT(
      COALESCE(step_tag, ''),
      COALESCE(customer_type_tag, ''),
      COALESCE(client_type, ''),
      COALESCE(request_type, ''),
      COALESCE(contact_motivation_tag, ''),
      COALESCE(contact_theme_tag, ''),
      COALESCE(contact_theme_detail_tag, '')
    )
  ) AS sk_taxonomy,
  status,
  type,
  tags,
  via_channel AS ticket_via,
  group_name,
  channel,
  priority,
  recipient,
  TO_JSON(custom_fields) AS custom_fields,
  custom_fields AS custom_fields_map,
  subject,
  description,
  CAST(GET_JSON_OBJECT(satisfaction_rating,'$.score') AS STRING) AS score,
  CAST(GET_JSON_OBJECT(satisfaction_rating,'$.reason') AS STRING) AS reason,
  CAST(GET_JSON_OBJECT(satisfaction_rating,'$.comment') AS STRING) AS comment,
  BOOLEAN(is_public) AS has_public_comments,
  ts_created,
  ts_created - INTERVAL 3 HOUR AS ts_created_brt,
  ts_updated,
  ts_updated - INTERVAL 3 HOUR AS ts_updated_brt,
  NOW() AS ts_load
FROM
  datalake_zendesk.tickets_current
