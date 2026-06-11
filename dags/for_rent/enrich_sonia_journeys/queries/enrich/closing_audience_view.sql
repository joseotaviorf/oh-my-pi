-- Sonia Closing audience view: one row per contract signatory from per-person contract-sent events.
-- Source: rent_flow_[tenant|owner]_contract_sent CDP events from 2026-04-24.
-- is_participant encodes three independently-expandable gates (all use the same binning_value):
--   Gate 0: number_of_signatories = 2,                                        threshold 0-100 (100 = fully open)
--   Gate 1: all contract signatories registered (every uuid_person NOT NULL),  threshold 0-100 (100 = fully open)
--   Gate 2: contract has any unregistered signatory (any uuid_person IS NULL), threshold 0-100 (100 = fully open)
-- PII note: stores contact PII (email, phone, name) as an approved reverse-DAG exception (feeds SFMC).
WITH
raw_sent_events AS (
  SELECT
    CAST(event_properties:id_rent_flow AS STRING) AS id_rent_flow,
    TRY_CAST(event_properties:id_contract AS INT) AS id_contract,
    TRY_CAST(event_properties:id_contract_person AS INT) AS id_contract_person,
    CAST(event_properties:person_uuid AS STRING) AS uuid_person,
    TRY_CAST(event_properties:id_house AS INT) AS id_house,
    ABS(CRC32(ENCODE(CONCAT(CAST(TRY_CAST(event_properties:id_house AS INT) AS STRING), '-', CAST(event_properties:id_tenant AS STRING)), 'utf-8'))) % 100 AS binning_value,
    CASE
      WHEN event_name = 'rent_flow_tenant_contract_sent' THEN 'tenant'
      ELSE 'owner'
    END AS user_role,
    ts_event
  FROM
    datalake_cdp_clean.transactional
  WHERE
    event_name IN ('rent_flow_tenant_contract_sent', 'rent_flow_owner_contract_sent')
    AND ts_event >= TIMESTAMP '2026-04-24 00:00:00'
),
contract_person_sent_events AS (
  SELECT
    id_rent_flow,
    id_contract,
    id_contract_person,
    uuid_person,
    id_house,
    binning_value,
    user_role,
    MIN(ts_event) AS ts_first_sent,
    MAX(ts_event) AS ts_last_sent,
    COUNT(*) AS n_sent
  FROM
    raw_sent_events
  GROUP BY
    id_rent_flow, id_contract, id_contract_person, uuid_person, id_house, binning_value, user_role
),
contract_signatories AS (
  SELECT
    id_contract,
    COUNT(DISTINCT id_contract_person) AS number_of_signatories
  FROM
    contract_person_sent_events
  GROUP BY
    id_contract
),
contract_registration_status AS (
  SELECT
    id_contract,
    SUM(CASE WHEN uuid_person IS NULL THEN 1 ELSE 0 END) = 0 AS all_signatories_registered,
    SUM(CASE WHEN uuid_person IS NULL THEN 1 ELSE 0 END) > 0 AS has_unregistered_signatory
  FROM
    contract_person_sent_events
  GROUP BY
    id_contract
),
contract_canceled_events AS (
  SELECT
    CAST(event_properties:id_rent_flow AS STRING) AS id_rent_flow,
    MAX(ts_event) AS ts_canceled
  FROM
    datalake_cdp_clean.transactional
  WHERE
    event_name = 'rent_flow_contract_canceled'
    AND ts_event >= TIMESTAMP '2026-04-24 00:00:00'
  GROUP BY
    CAST(event_properties:id_rent_flow AS STRING)
),
contract_signed_events AS (
  SELECT
    CAST(event_properties:id_rent_flow AS STRING) AS id_rent_flow,
    TRY_CAST(event_properties:id_contract_person AS INT) AS id_contract_person,
    MAX(ts_event) AS ts_signed
  FROM
    datalake_cdp_clean.transactional
  WHERE
    event_name IN ('rent_flow_tenant_contract_signed', 'rent_flow_owner_contract_signed')
    AND ts_event >= TIMESTAMP '2026-04-24 00:00:00'
  GROUP BY
    CAST(event_properties:id_rent_flow AS STRING),
    TRY_CAST(event_properties:id_contract_person AS INT)
)
SELECT
  CONCAT(sent.id_rent_flow, '-', CAST(sent.id_contract_person AS STRING)) AS pk_rent_flow_person,
  sent.id_house,
  sent.id_contract,
  sent.id_contract_person,
  sent.id_rent_flow,
  sent.uuid_person,
  CONCAT_WS(', ', CAST(house.address AS STRING), CAST(house.number AS STRING)) AS address_text,
  sent.user_role,
  cpc.user_email,
  cpc.user_phone,
  cpc.first_name AS user_first_name,
  canceled.id_rent_flow IS NOT NULL AS is_canceled,
  signed.id_contract_person IS NOT NULL AS is_signed,
  (
    -- Gate 0: exactly 2 signatories (main tenant and main owner), graduated rollout by first-sent date
    (sig.number_of_signatories = 2 AND (
      (sent.binning_value < 1  AND sent.ts_first_sent >= TIMESTAMP '2026-04-27 00:00:00' AND sent.ts_first_sent < TIMESTAMP '2026-04-28 00:00:00')
      OR (sent.binning_value < 3  AND sent.ts_first_sent >= TIMESTAMP '2026-04-28 00:00:00' AND sent.ts_first_sent < TIMESTAMP '2026-05-07 00:00:00')
      OR (sent.binning_value < 30 AND sent.ts_first_sent >= TIMESTAMP '2026-05-07 00:00:00' AND sent.ts_first_sent < TIMESTAMP '2026-05-09 00:00:00')
      OR (sent.binning_value < 50 AND sent.ts_first_sent >= TIMESTAMP '2026-05-09 00:00:00' AND sent.ts_first_sent < TIMESTAMP '2026-06-02 00:00:00')
      OR (sent.binning_value < 10 AND sent.ts_first_sent >= TIMESTAMP '2026-06-02 00:00:00')
    ))
    -- Gate 1: all signatories in this contract are registered
    OR (crs.all_signatories_registered AND sent.binning_value < 0)
    -- Gate 2: this contract has at least one unregistered signatory
    OR (crs.has_unregistered_signatory AND sent.binning_value < 0)
  ) AS is_participant,
  sent.n_sent,
  DATE_FORMAT(sent.ts_first_sent, 'yyyy-MM-dd HH:mm:ss') AS ts_first_sent,
  DATE_FORMAT(sent.ts_last_sent, 'yyyy-MM-dd HH:mm:ss') AS ts_last_sent,
  DATE_FORMAT(canceled.ts_canceled, 'yyyy-MM-dd HH:mm:ss') AS ts_canceled,
  DATE_FORMAT(signed.ts_signed, 'yyyy-MM-dd HH:mm:ss') AS ts_signed
FROM
  contract_person_sent_events AS sent
INNER JOIN
  datalake_sonia_journeys.closing_contract_person_view AS cpc
    ON sent.id_contract_person = cpc.id_contract_person
LEFT JOIN
  contract_canceled_events AS canceled
    ON sent.id_rent_flow = canceled.id_rent_flow
LEFT JOIN
  contract_signed_events AS signed
    ON sent.id_rent_flow = signed.id_rent_flow
    AND sent.id_contract_person = signed.id_contract_person
    AND signed.ts_signed > sent.ts_last_sent
LEFT JOIN
  contract_signatories AS sig
    ON sent.id_contract = sig.id_contract
LEFT JOIN
  contract_registration_status AS crs
    ON sent.id_contract = crs.id_contract
INNER JOIN
  datalake_ebdb_clean.house
    ON sent.id_house = house.id
LEFT JOIN
  dw_public.dim_person AS dp
    ON sent.uuid_person = dp.uuid_person
WHERE
  (dp.has_right_to_be_forgotten = false OR dp.has_right_to_be_forgotten IS NULL)