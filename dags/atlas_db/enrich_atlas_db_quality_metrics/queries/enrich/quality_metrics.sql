WITH amplitude_data AS (
  SELECT
    id_amplitude,
    id_session,
    id_event,
    id_user,
    dejavuid,
    operation_type,
    product,
    form_step,
    match_type,
    match_response,
    user_response,
    operation_customer_edition,
    device_type,
    ts_event,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.`183047_atlas_db_house_characteristics_events`
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND (
      dejavuid IS NOT NULL
      AND dejavuid <> 'null'
    )
),
auto_complete_events_ranked AS (
  SELECT
    amp.id_amplitude,
    amp.id_session,
    amp.id_event,
    amp.id_user,
    amp.dejavuid,
    'auto_complete' AS operation_type,
    amp.product,
    amp.form_step,
    amp.match_type,
    amp.device_type,
    CASE
      WHEN filled.key = 'totalArea' THEN 'area'
      WHEN filled.key = 'condominiumPerMonth' THEN 'condo'
      WHEN filled.key = 'bedroomCount' THEN 'bedrooms'
      WHEN filled.key = 'parkingSlots' THEN 'parking_lots'
      WHEN filled.key = 'houseType' THEN 'house_type'
      WHEN filled.key = 'bathroomCount' THEN 'bathrooms'
      WHEN filled.key = 'iptuPerYear' THEN 'iptu'
      WHEN filled.key = 'floor' THEN 'floor'
      WHEN filled.key = 'suitesCount' THEN 'suites'
    END AS characteristic_name,
    filled.value AS characteristic_value,
    amp.ts_event,
    amp.year,
    amp.month,
    amp.day,
    ROW_NUMBER() OVER(
      PARTITION BY amp.id_amplitude, amp.id_session, amp.dejavuid, filled.key
      ORDER BY amp.ts_event
    ) AS rn
  FROM
    amplitude_data AS amp
  LATERAL VIEW
    EXPLODE(MAP_ENTRIES(FROM_JSON(amp.match_response, 'MAP<STRING, STRING>'))) AS filled
  WHERE
    filled.key <> 'dejavuId'
),
auto_complete_events AS (
  SELECT
    id_amplitude,
    id_session,
    id_event,
    id_user,
    dejavuid,
    operation_type,
    product,
    form_step,
    match_type,
    device_type,
    characteristic_name,
    characteristic_value,
    ts_event,
    year,
    month,
    day
  FROM
    auto_complete_events_ranked
  WHERE
    rn = 1
),
customer_edition_events AS (
  SELECT
    amp.id_amplitude,
    amp.id_session,
    amp.id_event,
    amp.id_user,
    amp.dejavuid,
    amp.operation_type,
    amp.product,
    amp.form_step,
    amp.match_type,
    amp.device_type,
    filled.info AS characteristic_name,
    CASE
      WHEN filled.info = 'house_type' THEN filled.value
      WHEN filled.value RLIKE '\\.?\\d{{1,2}}$' THEN REGEXP_REPLACE(REGEXP_REPLACE(filled.value, '[\\.,]\\d{{1,2}}$', ''), '[^0-9]', '')
      WHEN filled.value RLIKE ',?\\d{{1,2}}$' THEN REGEXP_REPLACE(REGEXP_REPLACE(filled.value, '[\\.,]\\d{{1,2}}$', ''), '[^0-9]', '')
      ELSE regexp_replace(filled.value, '[^0-9]', '')
    END AS characteristic_value,
    amp.ts_event,
    amp.year,
    amp.month,
    amp.day
  FROM
    amplitude_data AS amp
  LATERAL VIEW
    EXPLODE(FROM_JSON(amp.user_response, 'ARRAY<STRUCT<info: STRING, value: STRING, type: STRING>>')) AS filled
  WHERE
    amp.operation_type = 'customer_edition'
    AND amp.operation_customer_edition = '[]'
  UNION ALL
  SELECT
    amp.id_amplitude,
    amp.id_session,
    amp.id_event,
    amp.id_user,
    amp.dejavuid,
    amp.operation_type,
    amp.product,
    amp.form_step,
    amp.match_type,
    amp.device_type,
    filled.info AS characteristic_name,
    CASE
      WHEN filled.info = 'house_type' THEN filled.value
      WHEN filled.value RLIKE '\\.?\\d{{1,2}}$' THEN REGEXP_REPLACE(REGEXP_REPLACE(filled.value, '[\\.,]\\d{{1,2}}$', ''), '[^0-9]', '')
      WHEN filled.value RLIKE ',?\\d{{1,2}}$' THEN REGEXP_REPLACE(REGEXP_REPLACE(filled.value, '[\\.,]\\d{{1,2}}$', ''), '[^0-9]', '')
      ELSE REGEXP_REPLACE(filled.value, '[^0-9]', '')
    END AS characteristic_value,
    amp.ts_event,
    amp.year,
    amp.month,
    amp.day
  FROM
    amplitude_data AS amp
  LATERAL VIEW
    EXPLODE(FROM_JSON(amp.operation_customer_edition, 'ARRAY<STRUCT<info: STRING, value: STRING, type: STRING>>')) AS filled
  WHERE
    amp.operation_type = 'customer_edition'
    AND amp.operation_customer_edition <> '[]'
)
SELECT
  cee.id_amplitude,
  cee.id_session,
  cee.id_event,
  cee.id_user,
  cee.dejavuid,
  CASE
    WHEN ace.characteristic_value IS NULL THEN 'user_generated_content'
    ELSE cee.operation_type
  END AS operation_type,
  cee.product,
  cee.form_step,
  cee.match_type,
  cee.device_type,
  cee.characteristic_name,
  cee.characteristic_value,
  ace.characteristic_value AS original_value,
  cee.characteristic_value - NULLIF(ace.characteristic_value, 0) AS difference_value,
  (cee.characteristic_value - ace.characteristic_value)/NULLIF(ace.characteristic_value, 0) AS difference_percentual,
  cee.ts_event,
  cee.year,
  cee.month,
  cee.day
FROM
  customer_edition_events AS cee
LEFT JOIN
  auto_complete_events AS ace
    ON ace.id_amplitude = cee.id_amplitude
      AND ace.id_session = cee.id_session
      AND ace.dejavuid = cee.dejavuid
      AND ace.characteristic_name = cee.characteristic_name
      AND COALESCE(ace.characteristic_value, '') <> cee.characteristic_value
WHERE
  cee.characteristic_value <> ''
UNION ALL
SELECT
  ace.id_amplitude,
  ace.id_session,
  ace.id_event,
  ace.id_user,
  ace.dejavuid,
  ace.operation_type,
  ace.product,
  ace.form_step,
  ace.match_type,
  ace.device_type,
  ace.characteristic_name,
  ace.characteristic_value,
  NULL AS original_value,
  NULL AS difference_value,
  NULL AS difference_percentual,
  ace.ts_event,
  ace.year,
  ace.month,
  ace.day
FROM
  auto_complete_events AS ace
