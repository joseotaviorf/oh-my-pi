WITH jaiminho_concierge_events AS (
  SELECT
    COALESCE(NULLIF(user_notifications.id_user, 0), ebdb_user.id) AS id_user,
    user_notifications.id_event AS id_contact,
    'Contact' AS event_name,
    'Online Classifieds' AS origin,
    'Online Classifieds' AS channel,
    'Concierge' AS agent,
    CASE
      WHEN GET_JSON_OBJECT(user_notifications.payload, '$.templateVariables.3') = 'para aluguel'
       OR GET_JSON_OBJECT(user_notifications.payload, '$.templateVariables.2') = 'para aluguel' THEN 'rent'
      WHEN GET_JSON_OBJECT(user_notifications.payload, '$.templateVariables.3') = 'à venda'
       OR GET_JSON_OBJECT(user_notifications.payload, '$.templateVariables.2') = 'à venda' THEN 'sale'
    END AS business_context,
    user_notifications.ts_created AS ts_event,
    user_notifications.year,
    user_notifications.month,
    user_notifications.day
  FROM
    datalake_jaiminho_clean.user_notifications AS user_notifications
  LEFT JOIN
    datalake_ebdb_clean.user AS ebdb_user
      ON ebdb_user.main_phone = user_notifications.destination
  WHERE
    user_notifications.action IN ('ConciergeContactSubmissionClassifieds_presentation', 'ConciergeContactSubmissionClassifieds')
    AND GET_JSON_OBJECT(user_notifications.payload, '$.body') LIKE '%Vi que se interessou por um imóvel%'
    AND (
      GET_JSON_OBJECT(user_notifications.payload, '$.templateVariables.4') = 'Chaves na Mão'
      OR GET_JSON_OBJECT(user_notifications.payload, '$.templateVariables.5') = 'Chaves na Mão'
    )
    AND user_notifications.year = 2026
    AND COALESCE(NULLIF(user_notifications.id_user, 0), ebdb_user.id) IS NOT NULL
    AND user_notifications.status != 'failed'
),
company_relation as (
    SELECT DISTINCT
        COALESCE(u.id, -1) AS sk_user,
        bc.type AS buyer_company_relation_type,
        bc.ts_started AS ts_start,
        IFNULL(bc.ts_finished,current_date()) AS ts_end
    FROM
        datalake_rede_platform_clean.buyer_company AS bc
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON bc.uuid_person = u.uuid_person
)
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
    WHEN bcr.buyer_company_relation_type = '3P'
    THEN 'TQC 3P'
    ELSE 'TQC 1P'
  END AS event_name,
  LOWER(tqc.origin) AS origin,
  CASE
    WHEN bcr.buyer_company_relation_type = '3P'
    THEN 'TQC 3P'
    ELSE 'TQC 1P' 
  END AS channel,
  CASE
    WHEN bcr.buyer_company_relation_type = '3P'
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
    company_relation AS bcr 
    ON bcr.sk_user = COALESCE(tqc.id_user_lead, tqc.lead_phone)
    and date(tqc.ts_created) between date(bcr.ts_start) and date(bcr.ts_end)
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
    WHEN channel = 'Facebook' THEN 'ZEBRA.hybr.acq.nonorg.na.d.appdisplay.facebook'
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
UNION ALL
SELECT
  id_user,
  id_contact,
  event_name,
  origin,
  CASE
    WHEN business_context = 'rent' THEN 'ZEBRA.rent.acq.nonorg.na.d.onlineclassifieds.chavesnamão'
    WHEN business_context = 'sale' THEN 'ZEBRA.sale.acq.nonorg.na.d.onlineclassifieds.chavesnamão'
  END AS channel,
  agent,
  business_context,
  ts_event,
  year,
  month,
  day
FROM
  jaiminho_concierge_events
