SELECT
  CAST(id_ticket AS BIGINT) AS sk_ticket,
  COALESCE(CAST(id_problem_ticket AS BIGINT), -1) AS sk_problem_ticket,
  COALESCE(id_assignee, -1) AS sk_assignee,
  COALESCE(id_requester, -1) AS sk_requester,
  COALESCE(id_submitter, -1) AS sk_submitter,
  COALESCE(id_group, -1) AS sk_group,
  COALESCE(id_house, -1) AS sk_house,
  COALESCE(id_contract, -1) AS sk_contract,
  COALESCE(id_session, -1) AS sk_session,
  COALESCE(id_call, -1) AS sk_call,
  COALESCE(id_job, -1) AS sk_job,
  MD5(analyst_email) AS sk_agent,
  COALESCE(CAST(DATE_FORMAT(ts_created, 'yMMdd') AS INTEGER), -1) AS sk_ticket_created_date,
  COALESCE(CAST(DATE_FORMAT(ts_updated, 'yMMdd') AS INTEGER), -1) AS sk_event_date,
  taxonomy_tags,
  status,
  channel,
  subject,
  type,
  via_channel,
  tags,
  TO_JSON(custom_fields) AS custom_fields,
  is_public,
  ts_created AS ts_ticket_created,
  ts_updated AS ts_event,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_zendesk.tickets
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
