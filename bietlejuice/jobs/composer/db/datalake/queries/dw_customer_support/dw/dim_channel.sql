SELECT
  MD5(CONCAT('call', COALESCE(direction, ''))) AS sk_channel,
  'call' AS channel,
  direction,
  NOW() AS ts_load
FROM
  datalake_customer_support.call
GROUP BY 1,2,3,4
UNION ALL
SELECT
  MD5('chat') AS sk_channel,
  'chat' AS channel,
  'inbound' AS direction,
  NOW() AS ts_load
FROM
  datalake_customer_support.chat
GROUP BY 1,2,3,4
UNION ALL
SELECT
  MD5(CONCAT('email', COALESCE(direction, ''))) AS sk_channel,
  'email' AS channel,
  direction,
  NOW() AS ts_load
FROM
  datalake_customer_support.email
GROUP BY 1,2,3,4
