SELECT
  MD5(CONCAT('call', tags, direction)) AS sk_channel,
  'call' AS channel,
  direction,
  tags,
  NOW() AS ts_load
FROM
  datalake_front_tickets.call
UNION ALL
SELECT
  MD5(CONCAT('chat', tags)) AS sk_channel,
  'chat' AS channel,
  'inbound' AS direction,
  tags,
  NOW() AS ts_load
FROM
  datalake_front_tickets.chat
UNION ALL
SELECT
  MD5(CONCAT('email', tags)) AS sk_channel,
  'email' AS channel,
  'inbound' AS direction,
  tags,
  NOW() AS ts_load
FROM
  datalake_front_tickets.email
