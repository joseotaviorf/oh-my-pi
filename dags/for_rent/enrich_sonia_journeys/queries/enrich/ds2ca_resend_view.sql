WITH docs_demand_resend_events AS (
  SELECT
    cdp_tx.id_event,
    cdp_tx.id_person AS uuid_person,
    TRY_CAST(JSON_EXTRACT_SCALAR(cdp_tx.event_properties, '$.id_house') AS INT) AS id_house,
    JSON_EXTRACT_SCALAR(cdp_tx.event_properties, '$.id_rent_flow') AS id_rent_flow,
    cdp_tx.ts_event
  FROM datalake_cdp_clean.transactional AS cdp_tx
  WHERE
    cdp_tx.event_name = 'rent_flow_tenant_documentation_resend'
    AND cdp_tx.application = 'rental-offer'
    AND cdp_tx.journey_step = 'documentation'
    AND (
        YEAR > YEAR(CURRENT_DATE - INTERVAL '1' DAY)
        OR (
          YEAR = YEAR(CURRENT_DATE - INTERVAL '1' DAY)
          AND MONTH > MONTH(CURRENT_DATE - INTERVAL '1' DAY)
        )
        OR (
          YEAR = YEAR(CURRENT_DATE - INTERVAL '1' DAY)
          AND MONTH = MONTH(CURRENT_DATE - INTERVAL '1' DAY)
          AND DAY >= DAY(CURRENT_DATE - INTERVAL '1' DAY)
        )
      )
    AND ts_event >= CURRENT_TIMESTAMP - INTERVAL '1' DAY
)
SELECT
  CONCAT(e.id_event, '-', e.uuid_person) AS pk_event_user,
  e.id_event,
  e.id_house,
  e.id_rent_flow,
  e.uuid_person,
  u.id AS id_user,
  u.email AS user_email,
  SPLIT(TRIM(u.name), ' ')[1] AS user_first_name,
  REPLACE(u.main_phone, '+', '') AS user_phone,
  CONCAT_WS(', ', h.address, h.number) AS address_text,
  ABS(CRC32(TO_UTF8(e.uuid_person))) % 100 AS binning_value,
  DATE_FORMAT(e.ts_event,  '%Y-%m-%d %T') AS ts_event
FROM docs_demand_resend_events AS e
  INNER JOIN datalake_ebdb_clean.user AS u
    ON e.uuid_person = u.uuid_person
  INNER JOIN datalake_ebdb_clean.house AS h
    ON e.id_house = h.id

