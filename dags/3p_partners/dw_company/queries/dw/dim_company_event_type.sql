SELECT DISTINCT
  CRC32(CONCAT(ce.event_type, ce.event_source)) AS sk_company_event_type,
  ce.event_type,
  ce.event_source,
  TRUE AS has_3p_access_control,
  NOW() AS ts_load
FROM
  datalake_hubspot.company_events AS ce