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
),
ivr_events AS (
  SELECT
    id_call,
    from_number,
    to_number,
    MIN(id_task) AS id_task,
    MIN(ts_created_local) AS ts_first_event
  FROM
    datalake_bigfone_twilio.call_ivr_events
  WHERE
    -- CX's exclusive phone number to plaquinhas contacts
    to_number IN ('+5511933058701', '+5531933007908', '+5540202507')
  GROUP BY
    1,2,3
),
flex_events AS (
  SELECT
    id_task,
    id_call,
    id_conversation,
    from_number,
    to_number,
    MIN(ts_created_local) AS ts_first_event
  FROM
    datalake_bigfone_twilio.call_flex_events
  WHERE
    -- CX's exclusive phone number to plaquinhas contacts
    to_number IN ('+5511933058701', '+5531933007908', '+5540202507')
  GROUP BY
    1,2,3,4,5
),
phone_users_number AS (
  SELECT
    COALESCE(ie.from_number, fe.from_number) AS from_phone_number,
    COALESCE(ie.ts_first_event, fe.ts_first_event) AS ts_event
  FROM
    ivr_events AS ie
  FULL JOIN flex_events AS fe
    ON fe.id_call = ie.id_call
),
chat_users_number AS (
  SELECT
    qmc.from_phone_number AS customer_phone,
    qmc.ts_created AS ts_event
  FROM
    datalake_quinto_messenger.task_event AS qmte
    INNER JOIN datalake_quinto_messenger.task AS qmt
      ON qmte.id_task = qmt.id_task
    INNER JOIN datalake_quinto_messenger.channel AS qmc
      ON qmt.id_channel = qmc.id_channel
  WHERE
    LOWER(qmte.task_queue_name) LIKE '%plaquinhas%'
  GROUP BY
    1,2
),
--  New CX taxonomies created to identify tickets about Plaquinhas. Effective from 17/10/2022.	
cx_taxonomy_phone_events AS (	
  SELECT	
    id_user,	
    ts_ticket_started AS ts_event	
  FROM 	
     datalake_customer_support.call 	
  WHERE 	
	contact_theme_detail_tag IN ( 	
	  'rental_listing_register_search_properties_sale_or_lease_signs' ,	
	  'rental_listing_register_sign_real_estate_info',	
    'house_plate_info', 
    'real_estate_information_plates') 	
	AND id_user IS NOT NULL	
    AND DATE(ts_ticket_started) >= DATE('2022-10-17')	
), 	
--  New CX taxonomies created to identify tickets about Plaquinhas. Effective from 17/10/2022.	
cx_taxonomy_chat_events AS (	
  SELECT	
    id_user,	
    ts_ticket_started AS ts_event	
  FROM 	
     datalake_customer_support.chat	
  WHERE 	
	contact_theme_detail_tag IN ( 	
	  'rental_listing_register_search_properties_sale_or_lease_signs' ,	
	  'rental_listing_register_sign_real_estate_info',	
    'house_plate_info', 
    'real_estate_information_plates') 	
	AND id_user IS NOT NULL	
    AND DATE(ts_ticket_started) >= DATE('2022-10-17')	
), 
contact_cx AS (
  SELECT
    user.id AS id_user,
    'Telefone' AS canal,
    ts_event
  FROM
    datalake_ebdb_user.user AS user
    JOIN phone_users_number AS pn
      ON pn.from_phone_number = user.main_phone
  WHERE
    user.id > 0
    AND DATE(ts_event) < DATE('2022-10-17')
  UNION ALL
  SELECT	
    id_user,	
    'Telefone' AS canal,	
    ts_event	
  FROM	
    cx_taxonomy_phone_events	
  UNION ALL
  SELECT
    user.id AS id_user,
    'Chat' AS canal,
    ts_event
  FROM
    datalake_ebdb_user.user AS user
    JOIN chat_users_number AS cn
      ON cn.customer_phone = user.main_phone
  WHERE
    user.id > 0
  UNION ALL
	SELECT	
    id_user,	
    'Chat' AS canal,	
    ts_event	
  FROM	
    cx_taxonomy_chat_events
  UNION ALL
  SELECT
    INT(id_user) AS id_user,
    canal,
    data_hora AS ts_event
  FROM
    datalake_gsheets_clean.users_cx_plaquinhas
  WHERE
    INT(id_user) > 0
)

SELECT
DISTINCT
  id_user,
  NULL AS id_contact,
  'Contact' AS event_name,
  'Placas' AS origin,
  canal AS channel,
  'CX' AS agent,
  ts_event,
  YEAR(ts_event) AS year,
  MONTH(ts_event) AS month,
  DAY(ts_event) AS day
FROM 
  contact_cx AS cx
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
UNION ALL

SELECT
DISTINCT
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