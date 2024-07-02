-- Legacy chat touchpoints
WITH legacy_chat_flow AS (
  SELECT DISTINCT
    user.id AS id_user,
    'Chat' AS contact_channel,
    qmc.ts_created AS ts_event
  FROM
    datalake_quinto_messenger.task_event AS qmte
  INNER JOIN
    datalake_quinto_messenger.task AS qmt
      ON qmte.id_task = qmt.id_task
  INNER JOIN
    datalake_quinto_messenger.channel AS qmc
      ON qmt.id_channel = qmc.id_channel
  INNER JOIN
    datalake_ebdb_user.user AS user
      ON qmc.from_phone_number = user.main_phone
  WHERE
    LOWER(qmte.task_queue_name) LIKE '%plaquinhas%'
    AND  user.id > 0
),

-- New chat flows
pre_chatbot_sessions AS (
  SELECT
    id_session,
    ts_started
  FROM
    datalake_greenseer_clean.session
  WHERE
    LOWER(id_pipeline) = 'whatsapp_direct_transfer'
    AND LOWER(GET_JSON_OBJECT(memory, '$.basic.session.department_key')) = 'rent_board_test'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_session ORDER BY ts_updated DESC) = 1
),

pos_chatbot_sessions AS (
  SELECT
    id_user,
    id_session,
    ts_started
  FROM
    datalake_greenseer.greenseer_session
  WHERE
    ts_started >= DATE('2023-03-20') -- data de inicio do bot de plaquinhas
    AND LOWER(id_pipeline) IN ('whatsapp_real_state_signs', 'whatsapp_real_estate_signs')
),

plaquinhas_sessions AS (
  SELECT
    gs.id_user,
    gs.ts_started AS ts_event
  FROM
    datalake_greenseer.greenseer_session AS gs
  INNER JOIN
    pre_chatbot_sessions AS pcs
      ON pcs.id_session = gs.id_session
  UNION ALL
  SELECT
    id_user,
    ts_started AS ts_event
  FROM
    pos_chatbot_sessions
),

total_chat AS (
  SELECT DISTINCT
    id_user,
    'Chat'AS contact_channel,
    ts_event
  FROM
    plaquinhas_sessions
  WHERE
    DATE(ts_event) >= DATE('2022-10-17')
    AND id_user IS NOT NULL
  UNION ALL
  SELECT
    id_user,
    contact_channel,
    ts_event
  FROM
    legacy_chat_flow
  WHERE
    DATE(ts_event) < DATE('2022-10-17')
    AND id_user IS NOT NULL
),

-- Phone calls to Plaquinhas exclusive numbers
ivr_events AS (
  SELECT
    id_call,
    from_phone_number AS from_number,
    to_phone_number AS to_number,
    MIN(id_task) AS id_task,
    MIN(ts_created - INTERVAL 3 HOUR) AS ts_first_event
  FROM
    datalake_bigfone.ivr_tasks
  WHERE
    -- CX's exclusive phone number to plaquinhas contacts
    (
      to_phone_number IN (
        "+5511933058701",
        "+5531933007908",
        "+5540202507"
      ) AND ts_created  - INTERVAL 3 HOUR < "2022-10-17"
    ) OR (
      to_phone_number LIKE "%40202507%"
      AND ts_created  - INTERVAL 3 HOUR >= "2022-10-17"
    )
  GROUP BY 1, 2, 3
),

flex_events AS (
  SELECT
    id_call,
    id_task,
    from_phone_number AS from_number,
    to_phone_number AS to_number,
    MIN(ts_created - INTERVAL 3 HOUR) AS ts_first_event
  FROM
    datalake_bigfone_clean.event
  WHERE
    -- CX's exclusive phone number to plaquinhas contacts
    workflow_name IN ('Assign to Anyone', 'Assign to Flex')
    AND (
      to_phone_number IN (
        "+5511933058701",
        "+5531933007908",
        "+5540202507"
      ) AND ts_created  - INTERVAL 3 HOUR < "2022-10-17"
    ) OR (
      to_phone_number LIKE "%40202507%"
      AND ts_created  - INTERVAL 3 HOUR >= "2022-10-17"
    )
  GROUP BY
    1, 2, 3, 4
),

total_phone AS (
  SELECT
    user.id AS id_user,
    'Telefone' AS contact_channel,
    COALESCE(ie.ts_first_event, fe.ts_first_event) AS ts_event
  FROM
    ivr_events AS ie
  FULL JOIN flex_events AS fe
    ON fe.id_call = ie.id_call
  INNER JOIN
    datalake_ebdb_user.user AS user
    ON COALESCE(ie.from_number, fe.from_number) = user.main_phone
  WHERE
    user.id > 0
),

plaquinhas_offline_touchpoints AS (
  SELECT
    id_user,
    contact_channel,
    ts_event
  FROM
    total_chat
  UNION ALL
  SELECT
    id_user,
    contact_channel,
    ts_event
  FROM
    total_phone
  UNION ALL
  SELECT
    INT(id_user) AS id_user,
    canal AS contact_channel,
    TO_TIMESTAMP(data_hora) AS ts_event
  FROM
    datalake_gsheets_clean.users_cx_plaquinhas
  WHERE
    INT(id_user) > 0
)

SELECT DISTINCT
  id_user,
  (id_user || 0 || TO_UNIX_TIMESTAMP(ts_event)) AS id_contact,
  'Contact' AS event_name,
  'Placas' AS origin,
  contact_channel AS channel,
  'CX' AS agent,
  ts_event,
  YEAR(ts_event) AS year,
  MONTH(ts_event) AS month,
  DAY(ts_event) AS day
FROM
  plaquinhas_offline_touchpoints
