WITH raw_contract_person_event AS (
  SELECT
    CAST(JSON_EXTRACT_SCALAR(event_properties, '$.contractPersonId') AS INT) AS id_contract_person,
    REGEXP_REPLACE(JSON_EXTRACT_SCALAR(event_properties, '$.phone'), '[^0-9]', '') AS user_phone,
    JSON_EXTRACT_SCALAR(event_properties, '$.email') AS user_email,
    JSON_EXTRACT_SCALAR(event_properties, '$.name') AS full_name,
    ts_event
  FROM
    datalake_cdp_clean.transactional
  WHERE
    event_name IN ('tenant_added_to_contract', 'owner_added_to_contract')
    AND application = 'mainstreamer'
    AND journey_step = 'cross'
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
),
event_contract_person AS (
  SELECT
    id_contract_person,
    NULLIF(LOWER(TRIM(user_email)), '') AS user_email,
    NULLIF(user_phone, '') AS user_phone,
    SPLIT(TRIM(full_name), ' ')[1] AS first_name,
    TRIM(SUBSTRING(TRIM(full_name), LENGTH(SPLIT(TRIM(full_name), ' ')[1]) + 1)) AS last_name,
    ROW_NUMBER() OVER (
      PARTITION BY id_contract_person ORDER BY ts_event DESC
    ) AS rn
  FROM
    raw_contract_person_event
  WHERE
    id_contract_person IS NOT NULL
)
SELECT
  id_contract_person,
  user_email,
  CASE
    WHEN LENGTH(user_phone) <= 11 THEN CONCAT('55', user_phone)
    ELSE user_phone
  END AS user_phone,
  first_name,
  last_name
FROM
  event_contract_person
WHERE
    rn = 1

