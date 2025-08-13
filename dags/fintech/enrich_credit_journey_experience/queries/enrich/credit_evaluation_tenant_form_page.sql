WITH union_tenant_form_events AS (
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation form page" AS event_source,
    event_properties,
    NULL AS drop_clicked_page,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    NULL AS tenant_type,
    NULL AS number_of_proponents,
    NULL AS group_type,
    GET_JSON_OBJECT(event_properties, "$.onbording_variant") AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.default_value") AS source_value,
    NULL AS user_requested_value,
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
    datalake_amplitude_clean.170698_evaluation_setvalue_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation form page" AS event_source,
    event_properties,
    NULL AS drop_clicked_page,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    NULL AS tenant_type,
    NULL AS number_of_proponents,
    NULL AS group_type,
    NULL AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    NULL AS source_value,
    NULL AS user_requested_value,
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
    datalake_amplitude_clean.170698_evaluation_selecttenants_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation form page" AS event_source,
    event_properties,
    NULL AS drop_clicked_page,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    get_json_object(event_properties, "$.tenant_type") AS tenant_type,
    NULL AS number_of_proponents,
    get_json_object(event_properties, "$.tenants_group") AS group_type,
    NULL AS entry_point,
    get_json_object(event_properties, "$.source") AS source,
    NULL AS source_value,
    NULL AS user_requested_value,
    version_name,
    device_family,
    city,
    region,
    country,
    IF(
      get_json_object(event_properties, "$.earlyCredit") IS NOT NULL,
      CAST(get_json_object(event_properties, "$.earlyCredit") AS BOOLEAN),
      FALSE
    ) AS is_early_credit,
    IF(
      get_json_object(event_properties, "$.credit_passport") IS NOT NULL
      OR get_json_object(event_properties, "$.credit_evaluation") IS NOT NULL,
      CAST(
        COALESCE(
          get_json_object(event_properties, "$.credit_passport"),
          get_json_object(event_properties, "$.credit_evaluation")
        ) AS BOOLEAN
      ),
      FALSE
    ) AS is_credit_passport,
    ts_event,
    year,
    month,
    day
  FROM
    datalake_amplitude_clean.170698_evaluation_tenantform_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation form page" AS event_source,
    event_properties,
    NULL AS drop_clicked_page,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    NULL AS tenant_type,
    GET_JSON_OBJECT(event_properties, "$.tenant_count") AS number_of_proponents,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    NULL AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    NULL AS source_value,
    NULL AS user_requested_value,
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
    datalake_amplitude_clean.170698_evaluation_tenantslist_submitted_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation form page" AS event_source,
    event_properties,
    NULL AS drop_clicked_page,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    NULL AS tenant_type,
    GET_JSON_OBJECT(event_properties, "$.tenant_count") AS number_of_proponents,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    NULL AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.default_value") AS source_value,
    GET_JSON_OBJECT(event_properties, "$.required_value") AS user_requested_value,
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
    datalake_amplitude_clean.170698_evaluation_summary_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation form page" AS event_source,
    event_properties,
    NULL AS drop_clicked_page,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    NULL AS tenant_type,
    GET_JSON_OBJECT(event_properties, "$.tenant_count") AS number_of_proponents,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    NULL AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.default_value") AS source_value,
    GET_JSON_OBJECT(event_properties, "$.required_value") AS user_requested_value,
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
    datalake_amplitude_clean.170698_evaluation_runevaluation_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  UNION ALL
  SELECT
    id_amplitude,
    id_session,
    id_user,
    event_type AS event_name,
    "Credit evaluation form page" AS event_source,
    event_properties,
    GET_JSON_OBJECT(event_properties, "$.current_page") AS drop_clicked_page,
    GET_JSON_OBJECT(event_properties, "$.city_name") AS credit_passport_city_name,
    NULL AS tenant_type,
    GET_JSON_OBJECT(event_properties, "$.tenant_count") AS number_of_proponents,
    GET_JSON_OBJECT(event_properties, "$.tenants_group") AS group_type,
    NULL AS entry_point,
    GET_JSON_OBJECT(event_properties, "$.source") AS source,
    GET_JSON_OBJECT(event_properties, "$.default_value") AS source_value,
    GET_JSON_OBJECT(event_properties, "$.required_value") AS user_requested_value,
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
    datalake_amplitude_clean.170698_evaluation_drop_clicked_events
  WHERE
    MAKE_DATE( year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  CAST(id_session AS BIGINT) AS id_session,
  CAST(id_amplitude AS BIGINT) AS id_amplitude,
  CAST(id_user AS BIGINT) AS id_user,
  version_name,
  device_family,
  city,
  region,
  country,
  event_name,
  event_source,
  drop_clicked_page,
  credit_passport_city_name,
  tenant_type,
  number_of_proponents,
  CASE
    WHEN GET_JSON_OBJECT(event_properties, "$.sharing_option") = 'ALONE' THEN 'single'
    WHEN GET_JSON_OBJECT(event_properties, "$.sharing_option") = 'WITH_PEOPLE' THEN 'multi'
    WHEN GET_JSON_OBJECT(event_properties, "$.sharing_option") = 'OTHERS' THEN 'others'
    ELSE group_type
  END AS group_type,
  entry_point,
  source,
  CAST(source_value AS DECIMAL(10, 2)) AS source_value,
  CAST(user_requested_value AS DECIMAL(10, 2)) AS user_requested_value,
  GET_JSON_OBJECT(event_properties, "$.current_page") AS current_page,
  is_early_credit,
  is_credit_passport,
  IF(
    is_credit_passport = false
    AND is_early_credit = false,
    TRUE,
    FALSE
  ) AS is_pos_offer,
  ts_event,
  year,
  month,
  day
FROM
  union_tenant_form_events
WHERE
  id_user IS NOT NULL
