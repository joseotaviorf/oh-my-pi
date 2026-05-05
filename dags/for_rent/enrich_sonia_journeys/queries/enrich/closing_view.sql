-- Rent-flow contract closing funnel from CDP transactional events; one row per contract_sent event x (tenant, owner).
-- Events from 2026-04-24 onward. Binning uses crc32 on "id_house-uuid_tenant" (see binning_value).
WITH
  contract_sent_events AS (
    SELECT
      e_sent.id_event,
      TRY_CAST(e_sent.event_properties:id_house AS INT) AS id_house,
      CAST(e_sent.event_properties:id_tenant AS STRING) AS uuid_tenant,
      CAST(e_sent.event_properties:id_owner AS STRING) AS uuid_owner,
      CAST(e_sent.event_properties:id_rent_flow AS STRING) AS id_rent_flow,
      CAST(e_sent.event_properties:id_contract AS INT) AS id_contract,
      e_sent.ts_event AS ts_sent
    FROM
      datalake_cdp_clean.transactional AS e_sent
    WHERE
      e_sent.event_name = 'rent_flow_contract_sent'
      AND e_sent.ts_event >= TIMESTAMP '2026-04-24 00:00:00'
  ),
  contract_canceled_events AS (
    SELECT
      CAST(e_canceled.event_properties:id_rent_flow AS STRING) AS id_rent_flow,
      e_canceled.id_event,
      e_canceled.ts_event AS ts_canceled
    FROM
      datalake_cdp_clean.transactional AS e_canceled
    WHERE
      e_canceled.event_name = 'rent_flow_contract_canceled'
      AND e_canceled.ts_event >= TIMESTAMP '2026-04-24 00:00:00'
  ),
  contract_signed_events AS (
    SELECT
      CAST(e_signed.event_properties:id_rent_flow AS STRING) AS id_rent_flow,
      e_signed.id_event,
      e_signed.ts_event AS ts_signed
    FROM
      datalake_cdp_clean.transactional AS e_signed
    WHERE
      e_signed.event_name = 'rent_flow_contract_signed'
      AND e_signed.ts_event >= TIMESTAMP '2026-04-24 00:00:00'
  ),
  contract_party_events AS (
    SELECT
      CAST(e_party.event_properties:contractId AS INT) AS id_contract,
      CAST(e_party.event_properties:contractPersonId AS INT) AS id_contract_person
    FROM
      datalake_cdp_clean.transactional AS e_party
    WHERE
      e_party.event_name IN ('tenant_added_to_contract', 'owner_added_to_contract')
      AND e_party.ts_event >= TIMESTAMP '2026-04-24 00:00:00'
  ),
  contract_parties AS (
    SELECT
      id_contract,
      count(DISTINCT id_contract_person) AS number_of_signatories
    FROM
      contract_party_events
    GROUP BY
      id_contract
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
  u.email AS user_email,
  coalesce(cp.number_of_signatories, 0) AS number_of_signatories,
  abs(crc32(encode(concat(CAST(s.id_house AS STRING), '-', s.uuid_tenant), 'utf-8'))) % 100 AS binning_value,
  s.id_contract % 100 AS binning_value_contract_id
FROM
  split_users AS s
  INNER JOIN datalake_ebdb_clean.user AS u
    ON s.uuid_person = u.uuid_person
  INNER JOIN datalake_ebdb_clean.house AS h
    ON s.id_house = h.id
  LEFT JOIN contract_parties AS cp
    ON cp.id_contract = s.id_contract
WHERE
  s.uuid_person IS NOT NULL
