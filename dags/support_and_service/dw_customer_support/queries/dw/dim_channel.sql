SELECT DISTINCT
  MD5(CONCAT(channel, direction, ticket_origin)) AS sk_channel,
  channel,
  direction,
  ticket_origin AS origin,
  NOW() AS ts_load
FROM
  datalake_customer_support.tickets