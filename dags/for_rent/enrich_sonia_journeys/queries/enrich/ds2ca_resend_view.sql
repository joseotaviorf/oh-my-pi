WITH docs_demand_resend_events AS (
  SELECT
    id_event,
    id_person AS uuid_person,
    CAST(event_properties:id_house AS INT) AS id_house,
    CAST(event_properties:id_rent_flow AS STRING) AS id_rent_flow,
    ts_event
  FROM datalake_cdp_clean.transactional
  WHERE
    event_name = 'rent_flow_docs_demand_docs_resend'
    -- When we start using sfmc for this journey we need to change this datetime
    -- to a point right after the last hightouch execution will take place.
    AND ts_event >= TIMESTAMP '2026-01-01 00:00:00'
)
SELECT
  e.id_event,
  e.id_house,
  e.id_rent_flow,
  e.uuid_person,
  concat_ws(', ', CAST(h.address AS STRING), CAST(h.number AS STRING)) AS address_text,
  abs(crc32(encode(e.uuid_person, 'utf-8'))) % 100 AS binning_value,
  date_format(e.ts_event, 'yyyy-MM-dd HH:mm:ss') AS ts_event
FROM docs_demand_resend_events AS e
  LEFT JOIN datalake_ebdb_clean.house AS h
    ON e.id_house = h.id
