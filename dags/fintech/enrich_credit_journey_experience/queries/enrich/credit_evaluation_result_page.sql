WITH union_evaluation_result_events AS (
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    COALESCE(
      GET_JSON_OBJECT(event_properties, "$.passport_result"),
      GET_JSON_OBJECT(event_properties, "$.result_evaluation")
    ) AS credit_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.available_guarantees") AS available_guarantees,
    GET_JSON_OBJECT(event_properties, "$.result_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.credit_range") AS credit_range,
    NULL AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    COALESCE(
      GET_JSON_OBJECT(event_properties, "$.passport_result"),
      GET_JSON_OBJECT(event_properties, "$.result_evaluation")
    ) AS credit_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.available_guarantees") AS available_guarantees,
    GET_JSON_OBJECT(event_properties, "$.result_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.credit_range") AS credit_range,
    NULL AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_redoevaluation_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    COALESCE(
      GET_JSON_OBJECT(event_properties, "$.passport_result"),
      GET_JSON_OBJECT(event_properties, "$.result_evaluation")
    ) AS credit_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.available_guarantees") AS available_guarantees,
    GET_JSON_OBJECT(event_properties, "$.result_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.credit_range") AS credit_range,
    GET_JSON_OBJECT(event_properties, "$.next_page") AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_cta_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    COALESCE(
      GET_JSON_OBJECT(event_properties, "$.passport_result"),
      GET_JSON_OBJECT(event_properties, "$.result_evaluation")
    ) AS credit_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.available_guarantees") AS available_guarantees,
    GET_JSON_OBJECT(event_properties, "$.result_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.credit_range") AS credit_range,
    NULL AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_secondary_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    COALESCE(
      GET_JSON_OBJECT(event_properties, "$.passport_result"),
      GET_JSON_OBJECT(event_properties, "$.result_evaluation")
    ) AS credit_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.available_guarantees") AS available_guarantees,
    GET_JSON_OBJECT(event_properties, "$.result_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.credit_range") AS credit_range,
    NULL AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_search_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    NULL AS source_value,
    GET_JSON_OBJECT(event_properties, "$.result") AS credit_evaluation_result,
    NULL AS available_guarantees,
    NULL AS entry_point,
    NULL AS group_type,
    NULL AS user_pre_approved_value,
    NULL AS credit_range,
    NULL AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_action_bar_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
    SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    NULL AS source_value,
    NULL AS credit_evaluation_result,
    NULL AS available_guarantees,
    NULL AS entry_point,
    NULL AS group_type,
    NULL AS user_pre_approved_value,
    NULL AS credit_range,
    NULL AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_newevaluation_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    NULL AS source_value,
    NULL AS credit_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.guaranteeType") AS available_guarantees,
    NULL AS entry_point,
    NULL AS group_type,
    NULL AS user_pre_approved_value,
    NULL AS credit_range,
    NULL AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_senddocs_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    NULL AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    NULL AS source_value,
    NULL AS credit_passport_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.guaranteeType") AS available_guarantees,
    NULL AS entry_point,
    NULL AS group_type,
    NULL AS user_pre_approved_value,
    NULL AS credit_range,
    NULL AS next_page,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN),
      FALSE
    ) AS is_early_credit,
    IF(
      GET_JSON_OBJECT(event_properties, "$.credit_passport") IS NOT NULL OR GET_JSON_OBJECT(event_properties, "$.credit_evaluation") IS NOT NULL,
      CAST(COALESCE(GET_JSON_OBJECT(event_properties, "$.credit_passport"), GET_JSON_OBJECT(event_properties, "$.credit_evaluation")) AS BOOLEAN),
      FALSE
    ) AS is_credit_passport,
    ts_event,
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_guarantee_clicked
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    NULL AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    NULL AS source_value,
    NULL AS credit_passport_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.guaranteeType") AS available_guarantees,
    NULL AS entry_point,
    NULL AS group_type,
    NULL AS user_pre_approved_value,
    NULL AS credit_range,
    NULL AS next_page,
    IF(
      GET_JSON_OBJECT(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(GET_JSON_OBJECT(event_properties, "$.earlyCredit") AS BOOLEAN),
      FALSE
    ) AS is_early_credit,
    IF(
      GET_JSON_OBJECT(event_properties, "$.credit_passport") IS NOT NULL OR GET_JSON_OBJECT(event_properties, "$.credit_evaluation") IS NOT NULL,
      CAST(COALESCE(GET_JSON_OBJECT(event_properties, "$.credit_passport"), GET_JSON_OBJECT(event_properties, "$.credit_evaluation")) AS BOOLEAN),
      FALSE
    ) AS is_credit_passport,
    ts_event,
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_reservation_clicked_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit Evaluation Result Page" AS event_source,
    event_properties,
    country,
    region,
    city,
    version_name,
    device_family,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.source_value") AS source_value,
    COALESCE(
      GET_JSON_OBJECT(event_properties, "$.passport_result"),
      GET_JSON_OBJECT(event_properties, "$.result_evaluation")
    ) AS credit_evaluation_result,
    GET_JSON_OBJECT(event_properties, "$.available_guarantees") AS available_guarantees,
    GET_JSON_OBJECT(event_properties, "$.result_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    GET_JSON_OBJECT(event_properties, "$.preapproved_value") AS user_pre_approved_value,
    GET_JSON_OBJECT(event_properties, "$.credit_range") AS credit_range,
    NULL AS next_page,
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
    ts_processed,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_result_close_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  CAST(id_session AS BIGINT) AS id_session,
  CAST(id_amplitude AS BIGINT) AS id_amplitude,
  CAST(id_user AS BIGINT) AS id_user,
  event_name,
  event_source,
  country,
  region,
  city,
  version_name,
  device_family,
  credit_passport_city_name,
  source,
  CAST(source_value AS DECIMAL(10, 2)) AS source_value,
  UPPER(credit_evaluation_result) AS credit_evaluation_result,
  UPPER(available_guarantees) AS available_guarantees,
  entry_point,
  group_type,
  CAST(user_pre_approved_value AS DECIMAL(10, 2)) AS user_pre_approved_value,
  credit_range,
  next_page,
  is_early_credit,
  is_credit_passport,
  IF(is_credit_passport = false AND is_early_credit = false, TRUE, FALSE) AS is_pos_offer,
  ts_event,
  year,
  month,
  day
FROM
  union_evaluation_result_events
WHERE
  id_user IS NOT NULL
