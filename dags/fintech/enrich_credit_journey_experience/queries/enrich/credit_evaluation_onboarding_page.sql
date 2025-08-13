WITH get_evaluation_onboarding_events AS (
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Onboarding Page" AS event_source,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.onboarding_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    version_name,
    device_family,
    city,
    region,
    country,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN),
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
    datalake_amplitude_clean.170698_evaluation_onboarding_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Onboarding Page" AS event_source,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.onboarding_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    version_name,
    device_family,
    city,
    region,
    country,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN),
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
    datalake_amplitude_clean.170698_evaluation_onboarding_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Onboarding Page" AS event_source,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.onboarding_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    version_name,
    device_family,
    city,
    region,
    country,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN),
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
    datalake_amplitude_clean.170698_evaluation_onboarding_dismissed_events
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
  CAST(user_pre_approved_value AS DECIMAL(10, 2)) AS user_pre_approved_value,
  source,
  CAST(source_value AS DECIMAL(10, 2)) AS source_value,
  is_early_credit,
  is_credit_passport,
  IF(
    is_early_credit = FALSE
    AND is_credit_passport = FALSE,
    TRUE,
    FALSE
  ) AS is_pos_offer,
  ts_event,
  year,
  month,
  day
FROM
  get_evaluation_onboarding_events
WHERE
  id_user IS NOT NULL
