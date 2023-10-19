WITH
contact_secretaria AS (
  SELECT
    COALESCE(cmc.id_client,uemail.id) AS id_user,
    cmc.id AS sk_contact,
    'Contact' AS event_name,
    oc.origin_contact_name AS origem,
    mc.media_contact_name AS canal,
    'Secretaria' AS agent,
    cmc.ts_created AS ts_event
  FROM
    datalake_casa_mineira_crm_clean.contact AS cmc
  LEFT JOIN datalake_ebdb_clean.user AS u
    ON cmc.id_client = u.id
  LEFT JOIN datalake_ebdb_clean.user AS uemail
    ON LOWER(uemail.email) = LOWER(cmc.email)
  LEFT JOIN datalake_casa_mineira_crm_clean.origin_contact AS oc
    ON oc.id = cmc.id_origin
  LEFT JOIN datalake_casa_mineira_crm_clean.media_contact AS mc
    ON mc.id = cmc.id_media
)

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
SELECT DISTINCT
  id_user,
  sk_contact AS id_contact,
  event_name,
  origem AS origin,
  canal AS channel,
  agent,
  ts_event,
  YEAR(ts_event) AS year,
  MONTH(ts_event) AS month,
  DAY(ts_event) AS day
FROM 
  contact_secretaria AS cs
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
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