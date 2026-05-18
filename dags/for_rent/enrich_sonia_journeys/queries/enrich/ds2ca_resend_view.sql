WITH docs_demand_resend_events AS (
  SELECT
    id_event,
    id_person AS uuid_person,
    TRY_CAST(event_properties:id_house AS INT) AS id_house,
    CAST(event_properties:id_rent_flow AS STRING) AS id_rent_flow,
    ts_event
  FROM datalake_cdp_clean.transactional
  WHERE
    event_name = 'rent_flow_tenant_documentation_resend'
    -- SFMC handover cutover: this view feeds the SFMC pipeline only for events
    -- at/after 2026-05-18 13:00 BRT. Events strictly before that are still
    -- handled by the legacy Hightouch query. The malformed-payload window
    -- (Jan/Feb 2026) is well before the cutover, so no extra lower bound
    -- is needed.
    AND ts_event >= to_utc_timestamp(TIMESTAMP '2026-05-18 13:00:00', 'America/Sao_Paulo')
)
SELECT
  CONCAT(CAST(e.id_event AS STRING), '-', e.uuid_person) AS pk_event_user,
  e.id_event,
  e.id_house,
  e.id_rent_flow,
  e.uuid_person,
  u.id AS id_user,
  u.email AS user_email,
  split(trim(u.name), ' ')[0] AS user_first_name,
  replace(u.main_phone, '+', '') AS user_phone,
  concat_ws(', ', CAST(h.address AS STRING), CAST(h.number AS STRING)) AS address_text,
  abs(crc32(encode(e.uuid_person, 'utf-8'))) % 100 AS binning_value,
  date_format(e.ts_event, 'yyyy-MM-dd HH:mm:ss') AS ts_event
FROM docs_demand_resend_events AS e
  INNER JOIN datalake_ebdb_clean.user AS u
    ON e.uuid_person = u.uuid_person
  INNER JOIN datalake_ebdb_clean.house AS h
    ON e.id_house = h.id

