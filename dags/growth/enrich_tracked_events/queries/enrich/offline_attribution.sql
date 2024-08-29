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
UNION ALL 
SELECT
  COALESCE(id_user_lead,lead_phone) AS id_user,
  COALESCE(id_user_lead, lead_phone, id_referral_flow) AS id_contact,
  'TQC' AS event_name,
  LOWER(origin) AS origin,
  'TQC' AS channel,
  'TQC' AS agent,
  ts_created AS ts_event,
  YEAR(ts_created) AS year,
  MONTH(ts_created) AS month,
  DAY(ts_created) AS day
FROM datalake_tqc_referral.unified_lead_referral_flow
WHERE 
  status IN ('CONFIRMED','TRUE')