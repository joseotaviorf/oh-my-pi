WITH contract_created_events AS (
  SELECT
    TRY_CAST(JSON_EXTRACT_SCALAR(JSON_PARSE(event_properties), '$.id') AS INT) AS id_contract,
    TRY_CAST(JSON_EXTRACT_SCALAR(JSON_PARSE(event_properties), '$.house_id') AS INT) AS id_house,
    TRY_CAST(JSON_EXTRACT_SCALAR(JSON_PARSE(event_properties), '$.tenant_id') AS INT) AS id_tenant,
    ts_event
  FROM datalake_cdp_clean.transactional
  WHERE
    event_name = 'contract_created'
    AND application = 'mainstreamer'
    AND YEAR >= 2026
    AND ts_event >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
),
contract_created AS (
  SELECT
    id_contract,
    id_contract % 100 AS binning_value_contract_id,
    ABS(CRC32(TO_UTF8(CONCAT(
      CAST(id_house AS VARCHAR),
      '-',
      CAST(id_tenant AS VARCHAR)
    )))) % 100 AS binning_value,
    MIN(ts_event) AS ts_created
  FROM contract_created_events
  WHERE
    id_contract IS NOT NULL
  GROUP BY
    id_contract, id_house, id_tenant
),
contract_party_events AS (
  SELECT
    TRY_CAST(JSON_EXTRACT_SCALAR(JSON_PARSE(event_properties), '$.contractId') AS INT) AS id_contract,
    TRY_CAST(JSON_EXTRACT_SCALAR(JSON_PARSE(event_properties), '$.contractPersonId') AS INT) AS id_contract_person
  FROM datalake_cdp_clean.transactional
  WHERE
    event_name IN ('tenant_added_to_contract', 'owner_added_to_contract')
    AND application = 'mainstreamer'
    AND YEAR >= 2026
    AND ts_event >= CURRENT_TIMESTAMP - INTERVAL '7' DAY
),
contract_parties AS (
  SELECT
    id_contract,
    COUNT(DISTINCT id_contract_person) AS number_of_signatories
  FROM contract_party_events
  WHERE
    id_contract IS NOT NULL
  GROUP BY
    id_contract
),
contract_gates AS (
  SELECT
    created.id_contract,
    created.binning_value_contract_id,
    created.binning_value,
    COALESCE(parties.number_of_signatories, 0) AS number_of_signatories,
    created.ts_created
  FROM contract_created AS created
  LEFT JOIN contract_parties AS parties
    ON created.id_contract = parties.id_contract
)
SELECT
  id_contract,
  (
    (number_of_signatories = 2 AND (
      (binning_value_contract_id < 1  AND ts_created >= TIMESTAMP '2026-04-27 00:00:00' AND ts_created < TIMESTAMP '2026-04-28 00:00:00')
      OR (binning_value_contract_id < 3  AND ts_created >= TIMESTAMP '2026-04-28 00:00:00' AND ts_created < TIMESTAMP '2026-05-07 00:00:00')
      OR (binning_value_contract_id < 30 AND ts_created >= TIMESTAMP '2026-05-07 00:00:00' AND ts_created < TIMESTAMP '2026-05-09 00:00:00')
      OR (binning_value_contract_id < 50 AND ts_created >= TIMESTAMP '2026-05-09 00:00:00' AND ts_created < TIMESTAMP '2026-06-02 00:00:00')
      OR (binning_value_contract_id < 10 AND ts_created >= TIMESTAMP '2026-06-02 00:00:00')
    ))
    OR (binning_value < 0)
  ) AS is_participant,
  ts_created
FROM contract_gates
