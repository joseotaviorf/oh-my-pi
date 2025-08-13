WITH get_evaluation_listing_event AS (
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation card" AS event_source,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.anchor_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.anchor_position") AS entry_point_position,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    "listing" AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    NULL AS current_page,
    device_family,
    version_name,
    city,
    region,
    country,
    IF(
      GET_JSON_OBJECT(event_properties, "$.early_credit") IS NOT NULL,
      CAST(GET_JSON_OBJECT(event_properties, "$.early_credit") AS BOOLEAN),
      FALSE
    ) AS is_early_credit,
    IF(
      GET_JSON_OBJECT(event_properties, "$.credit_passport") IS NOT NULL
      OR GET_JSON_OBJECT(event_properties, "$.credit_evaluation") IS NOT NULL,
      CAST(
        COALESCE(
          GET_JSON_OBJECT(event_properties, "$.credit_passport"),
          GET_JSON_OBJECT(event_properties, "$.credit_evaluation")
        ) AS BOOLEAN
      ),
      FALSE
    ) AS is_credit_passport,
    ts_event,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_anchor_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation card" AS event_source,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.anchor_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.anchor_position") AS entry_point_position,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    "listing" AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    GET_JSON_OBJECT(event_properties, "$.current_page") AS current_page,
    device_family,
    version_name,
    city,
    region,
    country,
    IF(
      GET_JSON_OBJECT(event_properties, "$.early_credit") IS NOT NULL,
      CAST(GET_JSON_OBJECT(event_properties, "$.early_credit") AS BOOLEAN),
      FALSE
    ) AS is_early_credit,
    IF(
      GET_JSON_OBJECT(event_properties, "$.credit_passport") IS NOT NULL
      OR GET_JSON_OBJECT(event_properties, "$.credit_evaluation") IS NOT NULL,
      CAST(
        COALESCE(
          GET_JSON_OBJECT(event_properties, "$.credit_passport"),
          GET_JSON_OBJECT(event_properties, "$.credit_evaluation")
        ) AS BOOLEAN
      ),
      FALSE
    ) AS is_credit_passport,
    ts_event,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_anchor_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  CAST(id_session AS BIGINT) AS id_session,
  CAST(id_amplitude AS BIGINT) AS id_amplitude,
  CAST(id_user AS BIGINT) AS id_user,
  event_name,
  event_source,
  city,
  region,
  country,
  device_family,
  version_name,
  credit_passport_city_name,
  entry_point,
  entry_point_position,
  CAST(user_pre_approved_value AS DECIMAL(10, 2)) AS user_pre_approved_value,
  source,
  CAST(source_value AS DECIMAL(10, 2)) AS source_value,
  current_page,
  is_early_credit,
  is_credit_passport,
  ts_event,
  year,
  month,
  day
FROM
  get_evaluation_listing_event
WHERE
  id_user IS NOT NULL
