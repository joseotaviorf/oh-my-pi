-- Sonia Closing audience view: one row per contract signatory from per-person contract-sent events.
-- Source: rent_flow_[tenant|owner]_contract_sent CDP events from 2026-04.
-- is_participant encodes three independently-expandable gates (all use the same binning_value):
--   Gate 0: number_of_signatories = 2,                                        threshold 0-100 (100 = fully open)
--   Gate 1: all contract signatories registered (every uuid_person NOT NULL),  threshold 0-100 (100 = fully open)
--   Gate 2: contract has any unregistered signatory (any uuid_person IS NULL), threshold 0-100 (100 = fully open)
-- PII note: stores contact PII (email, phone, name) as an approved reverse-DAG exception (feeds SFMC).
WITH
rent_flow_events AS (
  SELECT
    JSON_EXTRACT_SCALAR(event_properties, '$.id_rent_flow')                                AS id_rent_flow,
    CAST(JSON_EXTRACT_SCALAR(event_properties, '$.id_contract_person') AS INTEGER)         AS id_contract_person,
    CAST(JSON_EXTRACT_SCALAR(event_properties, '$.id_contract')        AS INTEGER)         AS id_contract,
    JSON_EXTRACT_SCALAR(event_properties, '$.person_uuid')                                 AS uuid_person,
    CAST(JSON_EXTRACT_SCALAR(event_properties, '$.id_house') AS INTEGER)                   AS id_house,
    JSON_EXTRACT_SCALAR(event_properties, '$.id_tenant')                                   AS id_tenant,
    CASE WHEN event_name = 'rent_flow_tenant_contract_sent' THEN 'tenant' ELSE 'owner' END AS user_role,
    CASE
      WHEN event_name IN ('rent_flow_tenant_contract_sent',   'rent_flow_owner_contract_sent')   THEN 'sent'
      WHEN event_name IN ('rent_flow_tenant_contract_signed', 'rent_flow_owner_contract_signed') THEN 'signed'
      ELSE 'canceled'
    END AS kind,
    ts_event
  FROM datalake_cdp_clean.transactional
  WHERE 
    application = 'rental-offer'
    AND journey_step = 'on_contract'
    AND event_name IN (
        'rent_flow_tenant_contract_sent',   'rent_flow_owner_contract_sent',
        'rent_flow_tenant_contract_signed', 'rent_flow_owner_contract_signed',
        'rent_flow_contract_canceled')
    AND (
        YEAR > YEAR(CURRENT_DATE - INTERVAL '30' DAY)
        OR (
          YEAR = YEAR(CURRENT_DATE - INTERVAL '30' DAY)
          AND MONTH > MONTH(CURRENT_DATE - INTERVAL '30' DAY)
        )
        OR (
          YEAR = YEAR(CURRENT_DATE - INTERVAL '30' DAY)
          AND MONTH = MONTH(CURRENT_DATE - INTERVAL '30' DAY)
          AND DAY >= DAY(CURRENT_DATE - INTERVAL '30' DAY)
        )
      )
    AND ts_event >= CURRENT_TIMESTAMP - INTERVAL '30' DAY
    AND ts_event >= TIMESTAMP '2026-06-17 00:00:00'
),
flow_person AS (
  SELECT
    id_rent_flow,
    id_contract_person,
    MAX(CASE WHEN kind = 'sent' THEN id_contract  END) AS id_contract,
    MAX(CASE WHEN kind = 'sent' THEN uuid_person  END) AS uuid_person,
    MAX(CASE WHEN kind = 'sent' THEN id_house     END) AS id_house,
    MAX(CASE WHEN kind = 'sent' THEN id_tenant    END) AS id_tenant,
    MAX(CASE WHEN kind = 'sent' THEN user_role    END) AS user_role,
    MIN(CASE WHEN kind = 'sent' THEN ts_event     END) AS ts_first_sent,
    MAX(CASE WHEN kind = 'sent' THEN ts_event     END) AS ts_last_sent,
    COUNT(CASE WHEN kind = 'sent' THEN 1 END)          AS n_sent,
    MAX(CASE WHEN kind = 'signed'   THEN ts_event END) AS ts_signed,
    MAX(CASE WHEN kind = 'canceled' THEN ts_event END) AS ts_canceled_in_flow
  FROM rent_flow_events
  GROUP BY id_rent_flow, id_contract_person
),
-- Derive contract-level gates + cancel propagation via windows (no extra scan).
enriched AS (
  SELECT
    *,
    MAX(ts_canceled_in_flow) OVER (PARTITION BY id_rent_flow)                AS ts_canceled,
    COUNT(*)                 OVER (PARTITION BY id_contract)                 AS number_of_signatories,
    SUM(CASE WHEN uuid_person IS NULL THEN 1 ELSE 0 END)
                             OVER (PARTITION BY id_contract)                 AS n_unregistered,
    ABS(CRC32(TO_UTF8(CAST(id_house AS VARCHAR) || '-' || id_tenant))) % 100 AS binning_value,
    CASE WHEN ts_signed > ts_last_sent THEN ts_signed END                    AS ts_signed_eff
  FROM flow_person
)
SELECT
  e.id_rent_flow || '-' || CAST(e.id_contract_person AS VARCHAR) AS pk_rent_flow_person,
  e.id_house,
  e.id_contract,
  e.id_contract_person,
  e.id_rent_flow,
  e.uuid_person,
  CONCAT_WS(', ', house.address, house.number) AS address_text,
  e.user_role,
  cpc.user_email,
  cpc.user_phone,
  cpc.first_name AS user_first_name,
  e.ts_canceled   IS NOT NULL AS is_canceled,
  e.ts_signed_eff IS NOT NULL AS is_signed,
  (
    -- Gate 0: exactly 2 signatories, graduated rollout by first-sent date
    (e.number_of_signatories = 2
     AND (e.id_contract % 100) < CASE
        WHEN e.ts_first_sent >= CAST('2026-06-17 18:00:00' AS TIMESTAMP) THEN 50
        ELSE 0
     END)
    -- Gate 1: all signatories registered
    OR (e.n_unregistered = 0 AND e.binning_value < 0)
    -- Gate 2: contract has an unregistered signatory
    OR (e.n_unregistered > 0 AND e.binning_value < 0)
  ) AS is_participant,
  e.n_sent,
  DATE_FORMAT(e.ts_first_sent,  '%Y-%m-%d %T') AS ts_first_sent,
  DATE_FORMAT(e.ts_last_sent,   '%Y-%m-%d %T') AS ts_last_sent,
  DATE_FORMAT(e.ts_canceled,    '%Y-%m-%d %T') AS ts_canceled,
  DATE_FORMAT(e.ts_signed_eff,  '%Y-%m-%d %T') AS ts_signed
FROM enriched AS e
INNER JOIN datalake_sonia_journeys.closing_contract_person_view AS cpc
  ON e.id_contract_person = cpc.id_contract_person
INNER JOIN datalake_ebdb_clean.house
  ON e.id_house = house.id
WHERE e.n_sent > 0 -- drop canceled-only helper rows & signed-only persons