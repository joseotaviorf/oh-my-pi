SELECT
  id_user,
  id_contact,
  event_name,
  origin,
  channel,
  agent,
  NULL AS business_context,
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
  NULL AS business_context,
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
  NULL AS business_context,
  cs.ts_created_at as ts_event,
  year,
  month,
  day
FROM
  datalake_demand_contact_submission_clean.contact_submissions AS cs
GROUP BY ALL
UNION ALL 
SELECT
  COALESCE(tqc.id_user_lead, tqc.lead_phone) AS id_user,
  COALESCE(tqc.id_user_lead, tqc.lead_phone, tqc.id_referral_flow) AS id_contact,
  CASE
    WHEN agent.agent_type = 'CORRETOR_REDE'
    THEN 'TQC 3P'
    ELSE 'TQC 1P'
  END AS event_name,
  LOWER(tqc.origin) AS origin,
  CASE
    WHEN agent.agent_type = 'CORRETOR_REDE'
    THEN 'TQC 3P'
    ELSE 'TQC 1P'
  END AS channel,
  CASE
    WHEN agent.agent_type = 'CORRETOR_REDE'
    THEN 'TQC 3P'
    ELSE 'TQC 1P'
  END AS agent,
  NULL AS business_context,
  tqc.ts_created AS ts_event,
  YEAR(tqc.ts_created) AS year,
  MONTH(tqc.ts_created) AS month,
  DAY(tqc.ts_created) AS day
FROM
  datalake_tqc_referral.unified_lead_referral_flow AS tqc
LEFT JOIN
  datalake_ebdb_clean.agent_data AS agent
    ON agent.id = tqc.id_agent
WHERE
  status IN ('CONFIRMED', 'TRUE')
UNION ALL
SELECT 
  COALESCE(u.id, bqr.phone_number, bqr.id_business) AS id_user,
	id_contact AS id_contact,
  'Contact' AS event_name,
  'Placas' AS origin,
  'plaquinhas_ada_whatsapp' AS channel,
  'Secretaria' AS agent,
  NULL AS business_context,
  ts_contact_start AS ts_event,
  YEAR(ts_contact_start) AS year,
  MONTH(ts_contact_start) AS month,
  DAY(ts_contact_start) AS day
FROM 
  datalake_hmb_ada_clean.backoffices bqr 
  LEFT JOIN 
    datalake_ebdb_clean.user u 
    ON SUBSTRING(u.main_phone, 4) = COALESCE(bqr.phone_number, bqr.id_business)
WHERE 
  LENGTH(REPLACE(main_phone,'+','')) IN (12,13)
  AND COALESCE(bqr.phone_number, bqr.id_business) is not null
  AND bqr.id_channel = 1
  AND bqr.id_campaign = 62
UNION ALL
SELECT
  id_user,
  id_contact,
  event_name,
  origin,
  CASE 
    WHEN channel = 'Facebook' THEN 'ZEBRA.hybr.acq.nonorg.na.d.webdisplay.facebook'
    WHEN channel = 'Placas' THEN CONCAT('ZEBRA.', CASE WHEN LOWER(business_context) = 'hybrid' THEN 'hybr' ELSE LOWER(business_context) END, '.acq.nonorg.na.d.placas.na')
    WHEN channel = 'Online Classifieds' THEN CONCAT(
      'ZEBRA.', 
      CASE WHEN LOWER(business_context) = 'hybrid' THEN 'hybr' ELSE LOWER(business_context) END, 
      '.acq.nonorg.na.d.onlineclassifieds.', 
      CASE 
        WHEN source IN ('Imovelweb', 'Chaves na Mão') THEN LOWER(REPLACE(source, ' ', ''))
        ELSE 'na'
      END
    )
    ELSE channel
  END AS channel,
  agent,
  business_context,
  ts_event,
  year,
  month,
  day
FROM
    datalake_tracked_events.concierge_attribution
