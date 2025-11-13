WITH message_summary AS (
  SELECT DISTINCT
    t.id_ticket,
    'BR' AS country_code,
    CAST(GET_JSON_OBJECT(evt.event_payload, '$.DateCreated') AS TIMESTAMP) AS ts_created_message,
    cht.ts_created AS ts_ticket_started,
    cht.ts_ended AS ts_ticket_ended,
    REPLACE(GET_JSON_OBJECT(evt.event_payload, '$.Body'), ';', ',') AS message,
    GET_JSON_OBJECT(evt.event_payload, '$.From') AS message_from
  FROM
    datalake_customer_support.chats AS cht
  LEFT JOIN
    datalake_customer_support.tickets AS t
      ON t.id_session = cht.id_session
      AND t.channel = 'chat'
  INNER JOIN
    datalake_quinto_messenger_clean.channel AS ch
      ON cht.id_session = ch.id_session
  INNER JOIN
    datalake_quinto_messenger_clean.channel_event AS evt
      ON evt.id_channel = ch.id_channel
  LEFT JOIN
    datalake_support_users.analysts AS a
      ON cht.worker_email = a.email
  WHERE
    cht.queue_name IN (
      'CX Visitas [FRONT] [PRE]',
      'CX Propostas [FRONT] [PRE]',
      'CX Mudança [FRONT] [POS]',
      'CX Parceiros [FRONT] [PRE]',
      'CX Parceiros da Portaria [FRONT] [PRE]',
      'Consultores imobiliários 5A',
      'CX Ação Plaquinhas [FRONT] [PRE]',
      'CX Pagamentos [FRONT] [POS]',
      'CX Reparos [FRONT] [POS]',
      'CX Rescisão [FRONT] [POS]',
      'CX Compra e Venda [FRONT] [PRE] [POS]',
      'CX Parceiros Compra e Venda [FRONT]',
      'CX Durante a locação e reparos [POS] [FRONT]',
      'CX Entrada no imóvel [ONB] [POS] [FRONT]',
      'CX Mudança [FRONT] [POS]',
      'CX Pagamentos [FRONT] [POS]',
      'CX Pagamentos N1 [PAY] [POS] [FRONT]',
      'CX Parceiros [FRONT] [PRE]',
      'CX Parceiros Compra e Venda [FRONT]',
      'CX Parceiros da Portaria [FRONT] [PRE]',
      'CX Propostas [FRONT] [PRE]',
      'CX PROPOSTAS CALL/CHAT [PRO][PRE][FRONT]',
      'CX Reparos [FRONT] [POS]',
      'CX Rescisão [FRONT] [POS]',
      'CX Rescisão e Vistoria [OFF] [POS] [FRONT]',
      'CX Visitas [FRONT] [PRE]',
      'CX Visitas N1 & N2 [VIS] [PRE] [FRONT] [OUT]',
      'PARTNERS/CIQ [FRONT] [PRE]',
      'ProOwners [FRONT] [PRE] [POS]'
      )
    AND a.organization IN ('webhelp', 'webhelpbr')
    AND DATE(cht.ts_ended) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  id_ticket,
  country_code,
  ts_ticket_started,
  ts_ticket_ended,
  ts_created_message,
  message,
  CASE
    WHEN message_from LIKE '%whatsapp%' THEN 'client'
    ELSE message_from
  END AS message_from,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  message_summary
