WITH 
main_users AS (
  SELECT
    id AS sk_user,
    LOWER(email) AS email,
    REPLACE(main_phone,'+','') AS main_phone
  FROM 
    datalake_ebdb_clean.user
  WHERE 
    LENGTH(REPLACE(main_phone,'+','')) IN (12,13)
    AND SUBSTRING(main_phone,1,3) = '+55'
    AND TRY_CAST(SUBSTRING(main_phone,4,2) AS INT) BETWEEN 11 AND 99
    AND TRY_CAST(SUBSTRING(main_phone,6,1) AS INT) BETWEEN 2 AND 9
    AND TRY_CAST(SUBSTRING(main_phone,6,9) AS INT) NOT IN (111111111,222222222,333333333,444444444,555555555,666666666,777777777,888888888,999999999)
    AND TRY_CAST(SUBSTRING(main_phone,6,8) AS INT) NOT IN (11111111,22222222,33333333,44444444,55555555,66666666,77777777,88888888,99999999)
),
users AS (
  SELECT 
    v.id AS sk_visitor,
    COALESCE(v.id_external, u_email.sk_user,u_phone.sk_user) AS sk_user,   
    COALESCE(v.email, u_email.email, u_phone.email) AS email,    
    COALESCE(v.phone_number,u_email.main_phone, u_phone.main_phone) AS phone_number,
    v.ts_updated,
    ROW_NUMBER() OVER(PARTITION BY v.id ORDER BY v.ts_updated DESC) AS last_update_marker
  FROM
    datalake_hub_services_clean.visitor AS v
  LEFT JOIN main_users AS u_email
    ON UPPER(TRIM(u_email.email)) = UPPER(TRIM(v.email)) AND COALESCE(v.id_external,0) = 0
  LEFT JOIN main_users AS u_phone
    ON TRIM(u_phone.main_phone) = TRIM(REPLACE(phone_number,'+','')) AND COALESCE(v.id_external, 0) = 0
), 
contact_secretaria AS (
  SELECT 
    u.sk_user AS id_user,
    l.id AS sk_contact,
    'Contact' AS event_name,
    l.lead_type AS origem, 
    NULL AS canal,
    'Secretaria' AS agent,
    l.ts_created AS ts_event
  FROM datalake_hub_services_clean.lead AS l
  LEFT JOIN users AS u
    ON l.id_visitor = u.sk_visitor AND u.last_update_marker = 1
  WHERE TRUE 
    AND LOWER(l.lead_type) IN ('classified', 'inbound', 'sign', 'tqc_5a')
    AND sk_user IS NOT NULL
    AND DATE(l.ts_created) >= DATE('2023-01-01')
UNION ALL
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
  WHERE TRUE 
    AND DATE(cmc.ts_created) < DATE('2023-01-01')
)
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
