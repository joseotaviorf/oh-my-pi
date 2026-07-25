WITH tickets_session_as (
  SELECT 
    c.id_session,
    t.id_ticket,
    c.worker_email,
    t.ts_created AS ts_ticket_started,
    c.ts_ended AS ts_ticket_ended,
    a.organization
  FROM datalake_customer_support.chats AS c
  LEFT JOIN datalake_customer_support.tickets AS t
    ON t.id_session = c.id_session
    AND t.channel = 'chat'
  LEFT JOIN datalake_support_users.analysts AS a
      ON c.worker_email = a.email
  WHERE
    c.queue_name IN (
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
  AND DATE(c.ts_ended) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
), 
whatsapp_messages AS (
  SELECT DISTINCT
    ce.id_channel,
    ce.id AS id_message,
    COALESCE(chat.id_session, c.id_session) AS id_sauron_session,
    ce.from_phone_number AS user_sender,
    ce.message_body AS message,
    ce.ts_created,
    CASE
        WHEN from_phone_number = 'system' THEN 'Bot'
        WHEN from_phone_number LIKE '%whatsapp%' THEN 'User'
        WHEN REPLACE(REPLACE(from_phone_number,'_2E', '.'), '_40', '@')  LIKE '%@%' THEN 'Analyst'
        WHEN from_phone_number LIKE '%@%' THEN 'Analyst'
        ELSE NULL
      END AS user_type
  FROM
    datalake_quinto_messenger_clean.channel_event AS ce
  LEFT JOIN
    datalake_quinto_messenger_clean.channel AS c
      ON c.id_channel = ce.id_channel
      AND ce.ts_created < "2026-02-23T14:00:00.000+00:00"
  LEFT JOIN
    -- The addition of this source and date validation was due to a migration by the engineering team.
    -- In the future, we will no longer need the channel base as a source.
    datalake_quinto_messenger_clean.chat AS chat
      ON ce.id_channel = chat.id_channel
      AND ce.ts_created > "2026-02-23T14:00:00.000+00:00"
)
SELECT
  t.id_ticket,
  'BR' AS country_code,
  t.organization,
  m.message,
  m.ts_created AS ts_created_message,
  t.ts_ticket_started,
  t.ts_ticket_ended,
  CASE
    WHEN m.user_sender LIKE '%whatsapp%' THEN 'client'
    ELSE REPLACE(REPLACE(m.user_sender,'_2E', '.'), '_40', '@')
  END AS message_from,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load
FROM 
  tickets_session_as AS t
LEFT JOIN whatsapp_messages AS m
  ON t.id_session = m.id_sauron_session