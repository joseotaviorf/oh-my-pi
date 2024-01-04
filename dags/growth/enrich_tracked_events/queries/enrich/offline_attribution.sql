SELECT
  id_user,
  id_contact,
  event_name,
  origin,
  channel,
  agent,
  ts_event,
  year,
  month,
  day
FROM
  datalake_tracked_events.plaquinhas_offline_touchpoints
UNION ALL
SELECT
  id_user,
  id_contact,
  event_name,
  origin,
  channel,
  agent,
  ts_event,
  year,
  month,
  day
FROM
  datalake_tracked_events.secretaria_offline_touchpoints
UNION ALL
SELECT
  id_user,
  COALESCE(id_user,user_email,id_contact_submission) AS id_contact,
  'Contact' AS event_name,
  cs.origin AS origin,
  'demand-contact-submission' AS channel,
  'Secretaria' AS agent,
  cs.ts_created_at as ts_event,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_clean.contact_submissions AS cs
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10