-- Rent-flow contract closing funnel from CDP transactional events; one row per contract_sent event x (tenant, owner).
-- Events from 2026-04-01 onward. Binning uses Spark xxhash64 on "id_house-uuid_tenant" (see binning_value).
WITH
  contract_sent_events AS (
    SELECT
      e_sent.id_event,
      TRY_CAST(get_json_object(e_sent.event_properties, '$.id_house') AS INT) AS id_house,
      get_json_object(e_sent.event_properties, '$.id_tenant') AS uuid_tenant,
      get_json_object(e_sent.event_properties, '$.id_owner') AS uuid_owner,
      get_json_object(e_sent.event_properties, '$.id_rent_flow') AS id_rent_flow,
      e_sent.ts_event AS ts_sent
    FROM
      cdp_modeled_repo.tb_transactional AS e_sent
    WHERE
      e_sent.event_name = 'rent_flow_contract_sent'
      AND e_sent.ts_event >= TIMESTAMP '2026-04-01 00:00:00'
  ),
  contract_canceled_events AS (
    SELECT
      get_json_object(e_canceled.event_properties, '$.id_rent_flow') AS id_rent_flow,
      e_canceled.id_event,
      e_canceled.ts_event AS ts_canceled
    FROM
      cdp_modeled_repo.tb_transactional AS e_canceled
    WHERE
      e_canceled.event_name = 'rent_flow_contract_canceled'
      AND e_canceled.ts_event >= TIMESTAMP '2026-04-01 00:00:00'
  ),
  contract_signed_events AS (
    SELECT
      get_json_object(e_signed.event_properties, '$.id_rent_flow') AS id_rent_flow,
      e_signed.id_event,
      e_signed.ts_event AS ts_signed
    FROM
      cdp_modeled_repo.tb_transactional AS e_signed
    WHERE
      e_signed.event_name = 'rent_flow_contract_signed'
      AND e_signed.ts_event >= TIMESTAMP '2026-04-01 00:00:00'
  ),
  enriched_contract_sent AS (
    SELECT
      c_sent.*,
      c_canceled.id_event IS NOT NULL AS is_canceled,
      c_signed.id_event IS NOT NULL AS is_signed
    FROM
      contract_sent_events AS c_sent
      LEFT JOIN contract_canceled_events AS c_canceled
        ON c_sent.id_rent_flow = c_canceled.id_rent_flow
        AND c_canceled.ts_canceled > c_sent.ts_sent
      LEFT JOIN contract_signed_events AS c_signed
        ON c_sent.id_rent_flow = c_signed.id_rent_flow
        AND c_signed.ts_signed > c_sent.ts_sent
  ),
  split_users AS (
    SELECT
      e.*,
      user_map.user_role,
      CASE
        WHEN user_map.user_role = 'tenant' THEN e.uuid_tenant
        ELSE e.uuid_owner
      END AS uuid_person
    FROM
      enriched_contract_sent AS e
      CROSS JOIN (
        SELECT 'tenant' AS user_role
        UNION ALL
        SELECT 'owner' AS user_role
      ) AS user_map
  )
SELECT
  concat(CAST(s.id_event AS STRING), '-', s.uuid_person) AS pk_event_user,
  s.id_event,
  s.id_house,
  concat_ws(', ', CAST(h.address AS STRING), CAST(h.number AS STRING)) AS address_text,
  s.id_rent_flow,
  date_format(s.ts_sent, 'yyyy-MM-dd HH:mm:ss') AS ts_sent,
  s.is_canceled,
  s.is_signed,
  s.user_role,
  s.uuid_person,
  u.id AS id_user,
  abs(xxhash64(concat(CAST(s.id_house AS STRING), '-', s.uuid_tenant))) % 100 AS binning_value
FROM
  split_users AS s
  INNER JOIN datalake_ebdb_clean.user AS u
    ON s.uuid_person = u.uuid_person
  INNER JOIN datalake_ebdb_clean.house AS h
    ON s.id_house = h.id
WHERE
  s.uuid_person IS NOT NULL
