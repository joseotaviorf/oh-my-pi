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
    split_path[5] AS id_test_execution,
    results.file AS file,
    results.fullFile AS full_file,
    EXPLODE(results.suites) AS suites
  FROM results_set
)
SELECT
  id_test_execution,
  suites.uuid AS id_suite,
  pwa,
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
  dt AS dt_created
FROM suites_set
