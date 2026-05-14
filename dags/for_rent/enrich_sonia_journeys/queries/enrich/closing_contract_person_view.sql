WITH raw_contract_person_event AS (
  SELECT
    CAST(event_properties:contractPersonId AS INT) AS id_contract_person,
    REGEXP_REPLACE(CAST(event_properties:phone AS STRING), '[^0-9]', '') AS user_phone,
    CAST(event_properties:email AS STRING) AS user_email,
    CAST(event_properties:name AS STRING) AS full_name,
    ts_event
  FROM
    datalake_cdp_clean.transactional
  WHERE
    event_name IN ('tenant_added_to_contract', 'owner_added_to_contract')
    AND ts_event >= TIMESTAMP '2026-05-01 00:00:00'
),
event_contract_person AS (
  SELECT
    id_contract_person,
    NULLIF(LOWER(TRIM(user_email)), '') AS user_email,
    NULLIF(user_phone, '') AS user_phone,
    split(TRIM(full_name), ' ')[0] AS first_name,
    TRIM(SUBSTRING(TRIM(full_name), LENGTH(split(TRIM(full_name), ' ')[0]) + 1)) AS last_name,
    ROW_NUMBER() OVER (
      PARTITION BY id_contract_person ORDER BY ts_event DESC
    ) AS rn
  FROM
    raw_contract_person_event
  WHERE
    id_contract_person IS NOT NULL
),
latest_event_contract_person AS (
  SELECT
    id_contract_person,
    user_email,
    user_phone,
    first_name,
    last_name
  FROM
    event_contract_person
  WHERE
    rn = 1
),
lake_contract_person AS (
  SELECT
    id AS id_contract_person,
    NULLIF(LOWER(TRIM(email)), '') AS user_email,
    NULLIF(REGEXP_REPLACE(phone_number, '[^0-9]', ''), '') AS user_phone,
    split(TRIM(name), ' ')[0] AS first_name,
    TRIM(SUBSTRING(TRIM(name), LENGTH(split(TRIM(name), ' ')[0]) + 1)) AS last_name
  FROM
    datalake_ebdb_clean.contract_person
)
SELECT
  event.id_contract_person,
  COALESCE(lake.user_email, event.user_email) AS user_email,
  CASE
    WHEN COALESCE(lake.user_phone, event.user_phone) IS NULL THEN NULL
    WHEN LENGTH(COALESCE(lake.user_phone, event.user_phone)) <= 11 THEN CONCAT('55', COALESCE(lake.user_phone, event.user_phone))
    ELSE COALESCE(lake.user_phone, event.user_phone)
  END AS user_phone,
  COALESCE(lake.first_name, event.first_name) AS first_name,
  COALESCE(lake.last_name, event.last_name) AS last_name
FROM
  latest_event_contract_person AS event
LEFT JOIN
  lake_contract_person AS lake
    ON event.id_contract_person = lake.id_contract_person

