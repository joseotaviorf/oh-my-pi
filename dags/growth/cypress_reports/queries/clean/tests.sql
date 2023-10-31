WITH results_set AS (
  SELECT
    EXPLODE(results) AS results,
    SPLIT(INPUT_FILE_NAME(), '/') AS split_path
  FROM
    datalake_cypress_reports_raw.cypress_reports
),
suites_set AS (
  SELECT
    split_path[3] AS pwa,
    split_path[4] AS dt,
    split_path[5] AS test_execution_id,
    EXPLODE(results.suites) AS suites
  FROM results_set
),
tests_set AS (
  SELECT
    pwa,
    dt,
    test_execution_id,
    EXPLODE(suites.tests) AS tests
  FROM
    suites_set
)
SELECT
  test_execution_id AS id_test_execution,
  tests.parentUUID AS id_suite,
  tests.uuid AS id_test,
  pwa,  
  tests.code,
  tests.context,
  tests.duration,
  tests.err AS error_message,
  tests.fullTitle AS full_tile,
  tests.isHook AS is_hook,
  tests.pending AS is_pending,
  tests.pass AS has_passed,
  tests.skipped AS has_been_skipped,
  tests.fail AS has_failed,
  tests.timedOut AS has_timed_out,
  tests.speed,
  tests.state,
  tests.title,
  COALESCE(GET_JSON_OBJECT(tests.context, '$.value'), 0) as retry_count,
  dt AS dt_created
FROM tests_set
