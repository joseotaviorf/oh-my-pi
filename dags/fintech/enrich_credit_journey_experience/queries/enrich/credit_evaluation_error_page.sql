WITH get_error_events AS (
  SELECT
    id_session,
    id_amplitude,
    id_user,
    city,
    region,
    country,
    device_family,
    version_name,
    event_type AS event_name,
    "Error page" AS event_source,
    event_properties,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.error_type") AS error_type,
    GET_JSON_OBJECT(event_properties, "$.error_flow") AS error_flow,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(
        GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN
      ),
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
    datalake_amplitude_clean.170698_evaluation_error_viewed_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_session,
    id_amplitude,
    id_user,
    city,
    region,
    country,
    device_family,
    version_name,
    event_type AS event_name,
    "Error page" AS event_source,
    event_properties,
    NULL AS credit_passport_city_name,
    NULL AS error_type,
    NULL AS error_flow,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(
        GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN
      ),
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
    datalake_amplitude_clean.170698_evaluation_errordialog_viewed_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_session,
    id_amplitude,
    id_user,
    city,
    region,
    country,
    device_family,
    version_name,
    event_type AS event_name,
    "Error page" AS event_source,
    event_properties,
    NULL AS credit_passport_city_name,
    NULL AS error_type,
    NULL AS error_flow,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(
        GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN
      ),
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
    datalake_amplitude_clean.170698_evaluation_timeout_viewed_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_session,
    id_amplitude,
    id_user,
    city,
    region,
    country,
    device_family,
    version_name,
    event_type AS event_name,
    "Error page" AS event_source,
    event_properties,
    NULL AS credit_passport_city_name,
    NULL AS error_type,
    NULL AS error_flow,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(
        GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN
      ),
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
    datalake_amplitude_clean.170698_evaluation_timeout_result_clicked_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
  SELECT
    CAST(id_session AS bigint) AS id_session,
    CAST(id_amplitude AS bigint) AS id_amplitude,
    CAST(id_user AS bigint) AS id_user,
    city,
    region,
    country,
    device_family,
    version_name,
    event_name,
    event_source,
    credit_passport_city_name,
    error_type,
    error_flow,
    source,
    IF(is_credit_passport = false AND is_early_credit = false, TRUE, FALSE) AS is_pos_offer,
    is_early_credit,
    is_credit_passport,
    ts_event,
    year,
    month,
    day
  FROM
    get_error_events
  WHERE
    id_user IS NOT NULL
