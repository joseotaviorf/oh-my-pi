SELECT
  MD5(CONCAT('call', 'twilio', COALESCE(direction, ''))) AS sk_channel,
  'call' AS channel,
  direction,
  "twilio" AS provider,
  NOW() AS ts_load
FROM
  datalake_customer_support.call
GROUP BY 1,2,3,4,5
UNION ALL
SELECT
  MD5('chat', 'twilio') AS sk_channel,
  'chat' AS channel,
  'inbound' AS direction,
  "twilio" AS provider,
  NOW() AS ts_load
FROM
  datalake_customer_support.chat
GROUP BY 1,2,3,4,5
UNION ALL
SELECT
  MD5(CONCAT('email', 'zendesk', COALESCE(direction, ''))) AS sk_channel,
  'email' AS channel,
  direction,
  "zendesk" AS provider,
  NOW() AS ts_load
FROM
  datalake_customer_support.email
GROUP BY 1,2,3,4,5
UNION ALL
SELECT
  MD5(CONCAT('call', 'teravoz', COALESCE(direction, ''))) AS sk_channel,
  'call' AS channel,
  direction,
  "teravoz" AS provider,
  NOW() AS ts_load
FROM
  datalake_customer_support.historical_call
GROUP BY 1,2,3,4,5
UNION ALL
SELECT
  MD5('chat', 'zendesk_chat') AS sk_channel,
  'chat' AS channel,
  'inbound' AS direction,
  "zendesk_chat" AS provider,
  NOW() AS ts_load
FROM
  datalake_customer_support.historical_chat
GROUP BY 1,2,3,4,5