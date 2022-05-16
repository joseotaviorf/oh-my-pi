WITH
contact_secretaria AS (
  SELECT
    COALESCE(uemail.id, uphone.id) AS id_user,
    cmc.id AS sk_contact,
    'Contact' AS event_name,
    oc.origin_contact_name AS origem,
    mc.media_contact_name AS canal,
    'Secretaria' AS agent,
    cmc.ts_created AS ts_event
  FROM
    datalake_casa_mineira_crm_clean.contact AS cmc
    LEFT JOIN datalake_ebdb_clean.user AS uemail
      ON LOWER(uemail.email) = LOWER(cmc.email)
    LEFT JOIN datalake_ebdb_clean.user AS uphone
      ON '+55' || cmc.phone_number = uphone.main_phone
    LEFT JOIN datalake_casa_mineira_crm_clean.origin_contact AS oc
      ON oc.id = cmc.id_origin
    LEFT JOIN datalake_casa_mineira_crm_clean.media_contact AS mc
      ON mc.id = cmc.id_media
  WHERE
    COALESCE(uemail.id, uphone.id) > 0
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
  WHERE
    COALESCE(ie.to_number, fe.to_number) IN (
      '+5511933058701',
      '+5531933007908',
      '+5540202507'
    ) -- CX's exclusive phone number to plaquinhas contacts
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
contact_cx AS (
  SELECT
    user.id AS id_user,
    'Telefone' AS canal,
    ts_event
  FROM
    datalake_ebdb_user.user AS user
    JOIN phone_users_number AS pn
      ON pn.from_phone_number = user.main_phone
  UNION ALL
  SELECT
    user.id AS id_user,
    'Chat' AS canal,
    ts_event
  FROM
    datalake_ebdb_user.user AS user
    JOIN chat_users_number AS cn
      ON cn.customer_phone = user.main_phone
  UNION ALL
  SELECT
    INT(id_user) AS id_user,
    canal,
    data_hora AS ts_event
  FROM
    datalake_gsheets_clean.users_cx_plaquinhas
)

SELECT
DISTINCT id_user,
  sk_contact AS id_contact,
  event_name,
  origem AS origin,
  canal AS channel,
  agent,
  YEAR(ts_event) AS year,
  MONTH(ts_event) AS month,
  DAY(ts_event) AS day,
  ts_event
FROM contact_secretaria AS cs

UNION ALL

SELECT
  DISTINCT id_user,
  NULL AS id_contact,
  'Contact' AS event_name,
  'Placas' AS origin,
  canal AS channel,
  'CX' AS agent,
  YEAR(ts_event) AS year,
  MONTH(ts_event) AS month,
  DAY(ts_event) AS day,
  ts_event
FROM contact_cx AS cx
WHERE id_user > 0