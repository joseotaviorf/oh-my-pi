WITH base AS (
  SELECT
    file_path,
    test_type,
    repository,
    deploy_group,
    service,
    ci_build_id,
    run_date,
    year,
    month,
    day,
    FROM_JSON(
      content,
      'STRUCT<totalFlows:INT,failedFlows:INT,successfulFlows:INT,failedFlowNames:ARRAY<STRING>,hasFailures:BOOLEAN,suiteInfo:STRUCT<name:STRING,totalTimeInSeconds:DOUBLE,timestamp:STRING>,testCases:ARRAY<STRUCT<id:STRING,name:STRING,classname:STRING,timeInSeconds:DOUBLE,status:STRING,failureMessage:STRING,timestamp:STRING,failed:BOOLEAN,ownershipInfo:STRUCT<team:STRUCT<name:STRING,alias:STRING>,ownerEmail:STRING,tags:ARRAY<STRING>>,failedEndpoints:ARRAY<STRING>>>,performance:STRUCT<averageExecutionTimeInSeconds:DOUBLE,totalExecutionTimeInSeconds:DOUBLE>,maestroUrl:STRING,reportName:STRING,platform:STRING,environment:STRING,metadata:STRUCT<reportGeneratedAt:STRING,totalTestCases:INT,failedTestCasesCount:INT,successfulTestCasesCount:INT,teamsWithFailures:ARRAY<STRING>,allTeamsInvolved:ARRAY<STRING>>>'
    ) AS parsed
  FROM
    datalake_release_validations_tests_raw.playwright_results
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    AND file_path LIKE '%report.json%'
),
test_cases_exploded AS (
  SELECT
    base.file_path,
    base.test_type,
    base.repository,
    base.deploy_group,
    base.service,
    base.ci_build_id,
    base.run_date,
    base.year,
    base.month,
    base.day,
    base.parsed,
    test_case,
    test_case_index
  FROM
    base
  LATERAL VIEW
    POSEXPLODE_OUTER(COALESCE(base.parsed.testCases, ARRAY())) test_table AS test_case_index,
    test_case
  WHERE
    test_case IS NOT NULL
)
SELECT
  -- ids (0)
  tce.ci_build_id AS id_ci_build,
  tce.test_case.id AS id_test_case,
  CONCAT_WS(
    '|',
    tce.ci_build_id,
    tce.test_case.id,
    CAST(tce.test_case_index AS STRING)
  ) AS id_unique_test_result,
  -- non-ids (1)
  -- general properties (2)
  tce.file_path,
  tce.test_type,
  tce.repository,
  tce.deploy_group,
  tce.service,
  tce.parsed.suiteInfo.name AS suite_name,
  tce.parsed.suiteInfo.totalTimeInSeconds AS suite_total_time_seconds,
  tce.parsed.suiteInfo.timestamp AS suite_timestamp,
  tce.parsed.performance.averageExecutionTimeInSeconds AS performance_avg_execution_time_seconds,
  tce.parsed.performance.totalExecutionTimeInSeconds AS performance_total_execution_time_seconds,
  tce.parsed.maestroUrl AS maestro_url,
  tce.parsed.reportName AS report_name,
  tce.parsed.platform AS platform,
  tce.parsed.environment AS environment,
  tce.test_case.id AS test_case_id,
  tce.test_case.name AS test_case_name,
  tce.test_case.classname AS test_case_classname,
  tce.test_case.timeInSeconds AS test_case_time_seconds,
  tce.test_case.status AS test_case_status,
  tce.test_case.failureMessage AS test_case_failure_message,
  tce.test_case.timestamp AS test_case_timestamp,
  tce.test_case.failed AS test_case_failed,
  tce.test_case.ownershipInfo.team.name AS ownership_team_name,
  tce.test_case.ownershipInfo.team.alias AS ownership_team_alias,
  tce.test_case.ownershipInfo.ownerEmail AS ownership_owner_email,
  tce.test_case.ownershipInfo.tags AS ownership_tags,
  tce.test_case.failedEndpoints AS test_case_failed_endpoints,
  -- metrics/booleans (3)
  tce.parsed.totalFlows AS run_total_flows,
  tce.parsed.failedFlows AS run_failed_flows,
  tce.parsed.successfulFlows AS run_successful_flows,
  tce.parsed.hasFailures AS is_failures_run,
  tce.parsed.failedFlowNames AS run_failed_flow_names,
  tce.parsed.metadata.totalTestCases AS metadata_total_test_cases,
  tce.parsed.metadata.failedTestCasesCount AS metadata_failed_test_cases_count,
  tce.parsed.metadata.successfulTestCasesCount AS metadata_successful_test_cases_count,
  tce.parsed.metadata.teamsWithFailures AS metadata_teams_with_failures,
  tce.parsed.metadata.allTeamsInvolved AS metadata_all_teams_involved,
  SIZE(tce.test_case.failedEndpoints) AS failed_endpoints_count,
  SIZE(tce.test_case.ownershipInfo.tags) AS ownership_tags_count,
  CASE
    WHEN tce.test_case.status = 'SUCCESS' THEN TRUE
    ELSE FALSE
  END AS is_passed,
  COALESCE(tce.test_case.failed, FALSE) AS is_failed,
  CASE
    WHEN tce.test_case.status = 'FAILED' THEN TRUE
    ELSE FALSE
  END AS is_status_failed,
  tce.test_case_index AS test_case_index,
  -- dates/timestamps (4)
  tce.run_date AS dt_run,
  TO_TIMESTAMP(tce.parsed.suiteInfo.timestamp) AS ts_suite,
  TO_TIMESTAMP(tce.test_case.timestamp) AS ts_test_case,
  TO_TIMESTAMP(tce.parsed.metadata.reportGeneratedAt) AS ts_report_generated,
  DATE(TO_TIMESTAMP(tce.parsed.suiteInfo.timestamp)) AS dt_suite,
  DATE(TO_TIMESTAMP(tce.test_case.timestamp)) AS dt_test_case,
  DATE(
    TO_TIMESTAMP(tce.parsed.metadata.reportGeneratedAt)
  ) AS dt_report_generated,
  -- partitions (5)
  tce.year,
  tce.month,
  tce.day
FROM
  test_cases_exploded AS tce
