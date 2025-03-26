SELECT
  id_communication AS sk_communication,
  communication_type,
  status,
  entity_name,
  was_delivered,
  was_comm_sent_on_time,
  ts_sent,
  NOW() AS ts_load
FROM
  datalake_condo_monitoring.communication
