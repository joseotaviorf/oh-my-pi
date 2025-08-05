WITH base1 AS (
  SELECT
    id_user,
    ts_updated,
    MIN(CASE WHEN input_type = 'TEST_GROUP_FLAG' THEN is_in_test_group ELSE NULL END) AS is_in_test_group,
    MIN(CASE WHEN input_type = 'EARLY_CREDIT_ELIGIBILITY_FLAG' THEN is_early_credit_criteria_satisfied ELSE NULL END) AS is_early_credit_criteria_satisfied,
    MIN(CASE WHEN input_type = 'APP_VERSION_ELIGIBILITY_FLAG' THEN is_app_version_updated ELSE NULL END) AS is_app_version_updated,
    MIN(CASE WHEN input_type = 'FEATURE_ENABLED_FLAG' THEN is_feature_enabled ELSE NULL END) AS is_feature_enabled
  FROM
    datalake_docx.person_document_information
  WHERE
    input_type IN (
      'TEST_GROUP_FLAG',
      'APP_VERSION_ELIGIBILITY_FLAG',
      'EARLY_CREDIT_ELIGIBILITY_FLAG',
      'FEATURE_ENABLED_FLAG'
    )
  GROUP BY
    id_user, ts_updated
), base2 AS (
  SELECT
    id_user,
    ts_updated,
    CASE
      WHEN
        is_in_test_group IS NULL
      THEN
        FIRST_VALUE(is_in_test_group)
          IGNORE NULLS OVER (
            PARTITION BY id_user
            ORDER BY id_user, ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          )
      ELSE is_in_test_group
    END AS is_in_test_group,
    CASE
      WHEN
        is_early_credit_criteria_satisfied IS NULL
      THEN
        FIRST_VALUE(is_early_credit_criteria_satisfied)
          IGNORE NULLS OVER (
            PARTITION BY id_user
            ORDER BY id_user, ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          )
      ELSE is_early_credit_criteria_satisfied
    END AS is_early_credit_criteria_satisfied,
    CASE
      WHEN
        is_app_version_updated IS NULL
      THEN
        FIRST_VALUE(is_app_version_updated)
          IGNORE NULLS OVER (
            PARTITION BY id_user
            ORDER BY id_user, ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          )
      ELSE is_app_version_updated
    END AS is_app_version_updated,
    CASE
      WHEN
        is_feature_enabled IS NULL
      THEN
        FIRST_VALUE(is_feature_enabled)
          IGNORE NULLS OVER (
            PARTITION BY id_user
            ORDER BY id_user, ts_updated
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          )
      ELSE is_feature_enabled
    END AS is_feature_enabled
  FROM
    base1
), base3 AS (
  SELECT
    id_user,
    is_in_test_group,
    is_app_version_updated,
    is_early_credit_criteria_satisfied,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_updated) AS rn,
    MIN(is_in_test_group) OVER (PARTITION BY id_user) AS min_is_in_test_group,
    MAX(is_in_test_group) OVER (PARTITION BY id_user) AS max_is_in_test_group
  FROM
    base2
  WHERE
    DATE(ts_updated) >= DATE '2025-06-03'
),
base4 AS (
  SELECT
    id_user,
  CASE
    WHEN min_is_in_test_group <> max_is_in_test_group THEN 'c. both experiences (credit passport and early credit)'
    WHEN is_in_test_group = TRUE AND min_is_in_test_group = max_is_in_test_group THEN 'b. passport only'
    WHEN is_app_version_updated = TRUE AND is_early_credit_criteria_satisfied = TRUE THEN 'a. eligible'
    WHEN is_app_version_updated = FALSE AND is_early_credit_criteria_satisfied = FALSE THEN 'd. not eligible - app version and early credit criteria'
    WHEN is_app_version_updated = FALSE THEN 'e. not eligible - app version criteria'
    WHEN is_early_credit_criteria_satisfied = FALSE THEN 'f. not eligible - early credit criteria'
    ELSE 'z. to be classified'
  END AS group_details,
    DATE(ts_updated) AS dt_first_lpv
  FROM
    base3 AS b3
  WHERE
    rn = 1
)
SELECT
  id_user,
  group_details,
  CASE
    WHEN group_details = 'a. eligible' THEN 'a. control'
    WHEN group_details = 'b. passport only' THEN 'b. test'
    ELSE 'c. noise'
  END AS ab_test_group,
  DATE_DIFF(DAY, dt_first_lpv, CURRENT_DATE() - INTERVAL '1' DAY) AS days_engaged,
  CASE
    WHEN DATE_DIFF(DAY, dt_first_lpv, CURRENT_DATE() - INTERVAL '1' DAY) >= 7 THEN TRUE
    ELSE FALSE
  END AS lpv_time_completed_1w,
  CASE
    WHEN DATE_DIFF(DAY, dt_first_lpv, CURRENT_DATE() - INTERVAL '1' DAY) >= 14 THEN TRUE
    ELSE FALSE
  END AS lpv_time_completed_2w,
  CASE
    WHEN DATE_DIFF(DAY, dt_first_lpv, CURRENT_DATE() - INTERVAL '1' DAY) >= 28 THEN TRUE
    ELSE FALSE
  END AS lpv_time_completed_4w,
  dt_first_lpv
FROM
  base4
