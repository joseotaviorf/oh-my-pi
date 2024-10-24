SELECT
  subscriber_id AS id_subscriber,
  message_id AS id_message,
  created_at AS ts_created
FROM
    datalake_docpilot_raw.processedmessage
