WITH
  contract_sent_events AS (
    SELECT
      e_sent.id_event,
      CAST(
        JSON_VALUE(e_sent.event_properties, 'lax $.id_house') AS INTEGER
      ) AS id_house,
      JSON_VALUE(e_sent.event_properties, 'lax $.id_tenant') AS uuid_tenant,
      JSON_VALUE(e_sent.event_properties, 'lax $.id_owner') AS uuid_owner,
      JSON_VALUE(e_sent.event_properties, 'lax $.id_rent_flow') AS id_rent_flow,
      e_sent.ts_event AS ts_sent
    FROM
      cdp_modeled_repo.tb_transactional e_sent
    WHERE
      e_sent.event_name = 'rent_flow_contract_sent' -- Cutoff before experiment start datetime
      AND e_sent.ts_event >= TIMESTAMP '2026-04-01 00:00:00'
  ),
  contract_canceled_events AS (
    SELECT
      JSON_VALUE(e_canceled.event_properties, 'lax $.id_rent_flow') AS id_rent_flow,
      e_canceled.id_event,
      e_canceled.ts_event AS ts_canceled
    FROM
      cdp_modeled_repo.tb_transactional e_canceled
    WHERE
      e_canceled.event_name = 'rent_flow_contract_canceled' -- Cutoff before experiment start datetime
      AND e_canceled.ts_event >= TIMESTAMP '2026-04-01 00:00:00'
  ),
  contract_signed_events AS (
    SELECT
      JSON_VALUE(e_signed.event_properties, 'lax $.id_rent_flow') AS id_rent_flow,
      e_signed.id_event,
      e_signed.ts_event AS ts_signed
    FROM
      cdp_modeled_repo.tb_transactional e_signed
    WHERE
      e_signed.event_name = 'rent_flow_contract_signed' -- Cutoff before experiment start datetime
      AND e_signed.ts_event >= TIMESTAMP '2026-04-01 00:00:00'
  ),
  enriched_contract_sent AS (
    SELECT
      c_sent.*,
      c_canceled.id_event IS NOT NULL AS is_canceled,
      c_signed.id_event IS NOT NULL AS is_signed
    FROM
      contract_sent_events c_sent
      LEFT JOIN contract_canceled_events c_canceled ON c_sent.id_rent_flow = c_canceled.id_rent_flow
      AND c_canceled.ts_canceled > c_sent.ts_sent
      LEFT JOIN contract_signed_events c_signed ON c_sent.id_rent_flow = c_signed.id_rent_flow
      AND c_signed.ts_signed > c_sent.ts_sent
  ),
  -- Creates a line for the owner and one for the tenant
  split_users AS (
    SELECT
      e.*,
      user_map.user_role,
      CASE
        WHEN user_map.user_role = 'tenant' THEN e.uuid_tenant
        ELSE e.uuid_owner
      END AS uuid_person
    FROM
      enriched_contract_sent e
      CROSS JOIN (
        VALUES
          ('tenant'),
          ('owner')
      ) AS user_map(user_role)
  )
SELECT
  CAST(s.id_event AS VARCHAR) || '-' || s.uuid_person AS pk_event_user,
  s.id_event,
  s.id_house,
  h.address || ', ' || h.number AS address_text,
  s.id_rent_flow,
  format_datetime(s.ts_sent, 'yyyy-MM-dd HH:mm:ss') AS ts_sent,
  s.is_canceled,
  s.is_signed,
  s.user_role,
  s.uuid_person,
  u.id AS id_user,
  ABS(
      from_big_endian_64(
        xxhash64(
          -- We use {id_house}-{uuid_tenant} as hash input so every contract
          -- created for a tenant in a given property always falls into the
          -- same group.
          to_utf8(CAST(s.id_house AS VARCHAR) || '-' || s.uuid_tenant)
        )
      )
    ) % 100 AS binning_value
FROM
  split_users s
  INNER JOIN datalake_ebdb_clean.user u ON s.uuid_person = u.uuid_person
  INNER JOIN datalake_ebdb_clean.house h ON s.id_house = h.id
WHERE
  s.uuid_person IS NOT NULL
