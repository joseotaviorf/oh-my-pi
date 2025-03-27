WITH
event_types AS (
  SELECT
    source,
    event_name,
    MIN(ts_event) AS ts_event
  FROM
    datalake_condo_monitoring.condo_monitoring_events
  GROUP BY ALL
),
event_numbered AS (
  SELECT
    ROW_NUMBER() OVER(ORDER BY ts_event) AS sk_event_type,
    source,
    event_name
  FROM
    event_types
)

SELECT
  cme.id_condo_monitoring_event AS sk_condo_monitoring_event,
  cme.id_contract AS sk_contract,
  COALESCE(cme.id_invoice, -1) AS sk_invoice,
  COALESCE(cme.id_communication, -1) AS sk_communication,
  en.sk_event_type,
  COALESCE(cme.id_house_listing, -1) AS sk_house_listing,
  COALESCE(cme.id_house, -1) AS sk_house,
  cme.uuid_owner,
  cme.uuid_tenant,
  cme.ts_event,
  NOW() AS ts_load
FROM
  datalake_condo_monitoring.condo_monitoring_events AS cme
JOIN
  event_numbered AS en
    ON cme.source = en.source
    AND cme.event_name = en.event_name
