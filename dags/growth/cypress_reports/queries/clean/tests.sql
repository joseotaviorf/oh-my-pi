WITH results_set AS (
  SELECT
    id_test_execution,
    EXPLODE(results) AS results,
    pwa,
    dt
  FROM
    datalake_cypress_reports_raw.cypress_reports
),
suites_set AS (
  SELECT
    id_test_execution,
    EXPLODE(results.suites) AS suites,
    pwa,
    dt
  FROM results_set
),
tests_set AS (
  SELECT
    id_test_execution,
    EXPLODE(suites.tests) AS tests,
    pwa,
    dt
  FROM
    suites_set
)
SELECT
  id_test_execution,
  tests.parentUUID AS id_suite,
  tests.uuid AS id_test,
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
  pwa,
  dt
FROM tests_set
