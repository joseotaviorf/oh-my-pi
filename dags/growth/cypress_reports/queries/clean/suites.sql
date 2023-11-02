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
    results.file AS file,
    results.fullFile AS full_file,
    EXPLODE(results.suites) AS suites,
    pwa,
    dt
  FROM results_set
)
SELECT
  id_test_execution,
  suites.uuid AS id_suite,
  file,
  full_file,
  suites._timeout AS timeout,
  suites.afterHooks AS after_hooks,
  suites.beforeHooks AS before_hooks,
  suites.duration,
  suites.failures,
  suites.passes,
  suites.pending,
  suites.skipped,
  suites.title,
  suites.root AS is_root,
  suites.rootEmpty AS is_root_empty,
  pwa,
  dt
FROM suites_set
