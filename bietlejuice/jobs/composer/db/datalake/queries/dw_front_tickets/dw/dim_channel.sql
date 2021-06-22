SELECT
  MD5(CONCAT('call', COALESCE(tags, ''), COALESCE(direction, ''))) AS sk_channel,
  'call' AS channel,
  direction,
  tags,
  NOW() AS ts_load
FROM
  datalake_front_tickets.call
GROUP BY 1,2,3,4,5
UNION ALL
SELECT
  MD5(CONCAT('chat', COALESCE(tags, ''))) AS sk_channel,
  'chat' AS channel,
  'inbound' AS direction,
  tags,
  NOW() AS ts_load
FROM
  datalake_front_tickets.chat
GROUP BY 1,2,3,4,5
UNION ALL
SELECT
  MD5(CONCAT('email', COALESCE(tags, ''))) AS sk_channel,
  'email' AS channel,
  'inbound' AS direction,
  tags,
  NOW() AS ts_load
FROM
  datalake_front_tickets.email
GROUP BY 1,2,3,4,5
