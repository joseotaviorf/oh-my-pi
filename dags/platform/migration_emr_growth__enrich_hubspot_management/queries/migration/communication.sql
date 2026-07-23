SELECT
  id_communication,
  ids_associated_tickets,
  ids_associated_contacts,
  ids_associated_companies,
  ids_associated_deals,
  communication_channel_type,
  communication_logged_from,
  communication_body,
  ts_communication,
  ts_created,
  ts_updated,
  year,
  month,
  day
FROM (
  SELECT
    id_communication,
    ids_associated_tickets,
    ids_associated_contacts,
    ids_associated_companies,
    ids_associated_deals,
    communication_channel_type,
    communication_logged_from,
    communication_body,
    ts_communication,
    ts_created,
    ts_updated,
    year,
    month,
    day,
    ROW_NUMBER() OVER (PARTITION BY id_communication ORDER BY ts_updated DESC) AS _w
  FROM datalake_hubspot.communication_history
) AS _t
WHERE
  _w = 1
