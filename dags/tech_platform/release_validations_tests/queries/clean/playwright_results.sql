-- Playwright Test Data Clean Layer
-- Transforms raw JSON playwright test results into flattened test attempt records

WITH base_data AS (
  SELECT
    file_path,
    test_type,
    repository,
    deploy_group,
    run_date,
    ci_build_id,
    service,
    year,
    month,
    day,
    GET_JSON_OBJECT(content, '$.config.metadata.gitCommit.shortHash') AS commit_short_hash,
    GET_JSON_OBJECT(content, '$.config.metadata.gitCommit.hash') AS commit_hash,
    GET_JSON_OBJECT(content, '$.config.metadata.gitCommit.branch') AS commit_branch,
    GET_JSON_OBJECT(content, '$.config.metadata.actualWorkers') AS actual_workers,
    content
  FROM datalake_release_validations_tests_raw.playwright_results
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),

-- Generate suite indices
suite_indices AS (
  SELECT
    base_data.*,
    POSEXPLODE(SPLIT(REPEAT(',', 100), ',')) AS (suite_idx, _)
  FROM base_data
  WHERE GET_JSON_OBJECT(content, '$.suites') IS NOT NULL
),

-- Extract suite data
suites AS (
  SELECT
    file_path,
    test_type,
    repository,
    deploy_group,
    run_date,
    ci_build_id,
    service,
    year,
    month,
    day,
    commit_short_hash,
    commit_hash,
    commit_branch,
    actual_workers,
    GET_JSON_OBJECT(content, CONCAT('$.suites[', suite_idx, '].file')) AS spec_file,
    GET_JSON_OBJECT(content, CONCAT('$.suites[', suite_idx, ']')) AS suite_json,
    suite_idx
  FROM suite_indices
  WHERE GET_JSON_OBJECT(content, CONCAT('$.suites[', suite_idx, ']')) IS NOT NULL
),

-- Generate spec indices
spec_indices AS (
  SELECT
    suites.*,
    POSEXPLODE(SPLIT(REPEAT(',', 100), ',')) AS (spec_idx, _)
  FROM suites
),

-- Extract spec data
specs AS (
  SELECT
    file_path,
    test_type,
    repository,
    deploy_group,
    run_date,
    ci_build_id,
    service,
    year,
    month,
    day,
    commit_short_hash,
    commit_hash,
    commit_branch,
    actual_workers,
    spec_file,
    GET_JSON_OBJECT(suite_json, CONCAT('$.specs[', spec_idx, '].title')) AS spec_title,
    GET_JSON_OBJECT(suite_json, CONCAT('$.specs[', spec_idx, '].tags')) AS tags_json,
    GET_JSON_OBJECT(suite_json, CONCAT('$.specs[', spec_idx, ']')) AS spec_json,
    spec_idx
  FROM spec_indices
  WHERE GET_JSON_OBJECT(suite_json, CONCAT('$.specs[', spec_idx, ']')) IS NOT NULL
),

-- Generate test indices
test_indices AS (
  SELECT
    specs.*,
    POSEXPLODE(SPLIT(REPEAT(',', 100), ',')) AS (test_idx, _)
  FROM specs
),

-- Extract test data
tests AS (
  SELECT
    file_path,
    test_type,
    repository,
    deploy_group,
    run_date,
    ci_build_id,
    service,
    year,
    month,
    day,
    commit_short_hash,
    commit_hash,
    commit_branch,
    actual_workers,
    spec_file,
    spec_title,
    FROM_JSON(tags_json, 'ARRAY<STRING>') AS tags,
    GET_JSON_OBJECT(spec_json, CONCAT('$.tests[', test_idx, '].projectId')) AS project_id,
    GET_JSON_OBJECT(spec_json, CONCAT('$.tests[', test_idx, '].projectName')) AS project_name,
    GET_JSON_OBJECT(spec_json, CONCAT('$.tests[', test_idx, '].expectedStatus')) AS expected_status,
    GET_JSON_OBJECT(spec_json, CONCAT('$.tests[', test_idx, ']')) AS test_json,
    test_idx
  FROM test_indices
  WHERE GET_JSON_OBJECT(spec_json, CONCAT('$.tests[', test_idx, ']')) IS NOT NULL
),

-- Generate result/attempt indices
result_indices AS (
  SELECT
    tests.*,
    POSEXPLODE(SPLIT(REPEAT(',', 20), ',')) AS (result_idx, _)
  FROM tests
),

-- Extract attempt/result data
attempts AS (
  SELECT
    file_path,
    test_type,
    repository,
    deploy_group,
    run_date,
    ci_build_id,
    service,
    year,
    month,
    day,
    commit_short_hash,
    commit_hash,
    commit_branch,
    actual_workers,
    spec_file,
    spec_title,
    tags,
    project_id,
    project_name,
    expected_status,
    CAST(GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].retry')) AS INT) AS attempt,
    GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].status')) AS attempt_status,
    CAST(GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].duration')) AS BIGINT) AS duration_ms,
    GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].startTime')) AS start_time_str,
    CAST(GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].workerIndex')) AS INT) AS worker_index,
    CAST(GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].parallelIndex')) AS INT) AS parallel_index,
    GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].attachments')) AS attachments_json,
    GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].error.message')) AS error_message_direct,
    GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].error.stack')) AS error_stack_direct,
    GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].error.location.file')) AS error_file_direct,
    CAST(GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].error.location.line')) AS INT) AS error_line_direct,
    GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].errors[0].message')) AS error_message_arr,
    GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].errors[0].location.file')) AS error_file_arr,
    CAST(GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, '].errors[0].location.line')) AS INT) AS error_line_arr
  FROM result_indices
  WHERE GET_JSON_OBJECT(test_json, CONCAT('$.results[', result_idx, ']')) IS NOT NULL
)

SELECT
  file_path,
  test_type,
  repository,
  deploy_group,
  run_date AS dt_run,
  ci_build_id AS id_ci_build,
  service,
  year,
  month,
  day,
  commit_short_hash,
  commit_hash,
  commit_branch,
  actual_workers,
  spec_file,
  spec_title,
  tags,

  -- Device extracted from tags
  CASE
    WHEN ARRAY_CONTAINS(tags, 'device-mobile') THEN 'mobile'
    WHEN ARRAY_CONTAINS(tags, 'device-desktop') THEN 'desktop'
    ELSE NULL
  END AS device,

  -- Test type tag extracted from tags
  FILTER(tags, t -> t LIKE 'type-%')[0] AS test_type_tag,

  project_id AS id_project,
  project_name,
  expected_status,

  -- Attempt details
  attempt,
  attempt_status,
  duration_ms,
  TO_TIMESTAMP(start_time_str) AS ts_start_utc,
  worker_index,
  parallel_index,

  -- Attachments
  FROM_JSON(COALESCE(attachments_json, '[]'), 'ARRAY<STRUCT<name:STRING,contentType:STRING,path:STRING>>') AS attachments,
  SIZE(FROM_JSON(COALESCE(attachments_json, '[]'), 'ARRAY<STRING>')) AS attachments_count,
  COALESCE(attachments_json, '') LIKE '%video%' AS has_video,
  (COALESCE(attachments_json, '') LIKE '%screenshot%' OR COALESCE(attachments_json, '') LIKE '%image%') AS has_screenshot,
  (COALESCE(attachments_json, '') LIKE '%trace%' OR COALESCE(attachments_json, '') LIKE '%zip%') AS has_trace,

  -- Error handling
  COALESCE(error_message_direct, error_message_arr) AS error_message,
  COALESCE(error_stack_direct, '') AS error_stack,
  COALESCE(error_file_direct, error_file_arr) AS error_location_file,
  COALESCE(error_line_direct, error_line_arr) AS error_location_line,

  -- Failure reason classification
  CASE
    WHEN attempt_status = 'timedOut'
      OR COALESCE(error_message_direct, error_message_arr, '') LIKE '%Test timeout%' THEN 'timeout'
    WHEN COALESCE(error_message_direct, error_message_arr, '') LIKE '%expect(%' THEN 'assertion'
    WHEN attempt_status = 'failed' THEN 'other'
    ELSE NULL
  END AS failure_reason,

  -- Unique identifiers
  SHA1(
    CONCAT_WS(
      '|',
      spec_file,
      spec_title,
      COALESCE(project_id, '')
    )
  ) AS id_test,

  SHA1(
    CONCAT_WS(
      '|',
      CAST(run_date AS STRING),
      COALESCE(ci_build_id, ''),
      SHA1(
        CONCAT_WS(
          '|',
          spec_file,
          spec_title,
          COALESCE(project_id, '')
        )
      ),
      CAST(attempt AS STRING)
    )
  ) AS id_attempt,

  -- Unexpected result flag
  CASE
    WHEN LOWER(COALESCE(expected_status, '')) != LOWER(COALESCE(attempt_status, '')) THEN TRUE
    ELSE FALSE
  END AS is_unexpected

FROM attempts
