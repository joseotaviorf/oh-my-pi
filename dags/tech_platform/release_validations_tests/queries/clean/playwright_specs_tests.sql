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
    from_json(
      content,
      'STRUCT<config:STRUCT<version:STRING,workers:INT,rootDir:STRING,metadata:STRUCT<actualWorkers:INT,gitCommit:STRUCT<hash:STRING,shortHash:STRING,subject:STRING,branch:STRING,author:STRUCT<name:STRING,email:STRING,time:BIGINT>>>>,stats:STRUCT<startTime:STRING,duration:DOUBLE,expected:INT,skipped:INT,unexpected:INT,flaky:INT>>'
    ) AS parsed,
    from_json(
      get_json_object(content, '$.suites'),
      'ARRAY<STRING>'
    ) AS root_suites
  FROM datalake_release_validations_tests_raw.playwright_results
),
rooted AS (
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
    transform(
      coalesce(base.root_suites, array()),
      suite_json -> named_struct(
        'suite',
        from_json(suite_json, 'STRUCT<title:STRING,file:STRING,line:INT,column:INT,specs:ARRAY<STRUCT<title:STRING,id:STRING,file:STRING,line:INT,column:INT,ok:BOOLEAN,tags:ARRAY<STRING>,tests:ARRAY<STRUCT<timeout:INT,expectedStatus:STRING,projectId:STRING,projectName:STRING,status:STRING,results:ARRAY<STRUCT<workerIndex:INT,parallelIndex:INT,status:STRING,duration:INT,retry:INT,startTime:STRING,errors:ARRAY<STRUCT<message:STRING,stack:STRING>>,attachments:ARRAY<STRUCT<name:STRING,contentType:STRING,path:STRING>>,stdout:ARRAY<STRING>,stderr:ARRAY<STRING>>>>>>>,suites:ARRAY<STRING>>'),
        'depth',
        0,
        'path',
        filter(array(from_json(suite_json, 'STRUCT<title:STRING,file:STRING,line:INT,column:INT,specs:ARRAY<STRUCT<title:STRING,id:STRING,file:STRING,line:INT,column:INT,ok:BOOLEAN,tags:ARRAY<STRING>,tests:ARRAY<STRUCT<timeout:INT,expectedStatus:STRING,projectId:STRING,projectName:STRING,status:STRING,results:ARRAY<STRUCT<workerIndex:INT,parallelIndex:INT,status:STRING,duration:INT,retry:INT,startTime:STRING,errors:ARRAY<STRUCT<message:STRING,stack:STRING>>,attachments:ARRAY<STRUCT<name:STRING,contentType:STRING,path:STRING>>,stdout:ARRAY<STRING>,stderr:ARRAY<STRING>>>>>>>,suites:ARRAY<STRING>>').title), x -> x IS NOT NULL)
      )
    ) AS root_entries
  FROM base
),
suite_accum AS (
  SELECT
    rooted.file_path,
    rooted.test_type,
    rooted.repository,
    rooted.deploy_group,
    rooted.service,
    rooted.ci_build_id,
    rooted.run_date,
    rooted.year,
    rooted.month,
    rooted.day,
    rooted.parsed,
    aggregate(
      sequence(1, 20),
      named_struct(
        'pending',
        rooted.root_entries,
        'collected',
        filter(rooted.root_entries, entry -> FALSE)
      ),
      (state, _) ->
        named_struct(
          'pending',
          flatten(
            transform(
              state.pending,
              entry ->
                transform(
                  coalesce(entry.suite.suites, array()),
                  child_json -> named_struct(
                    'suite',
                    from_json(child_json, 'STRUCT<title:STRING,file:STRING,line:INT,column:INT,specs:ARRAY<STRUCT<title:STRING,id:STRING,file:STRING,line:INT,column:INT,ok:BOOLEAN,tags:ARRAY<STRING>,tests:ARRAY<STRUCT<timeout:INT,expectedStatus:STRING,projectId:STRING,projectName:STRING,status:STRING,results:ARRAY<STRUCT<workerIndex:INT,parallelIndex:INT,status:STRING,duration:INT,retry:INT,startTime:STRING,errors:ARRAY<STRUCT<message:STRING,stack:STRING>>,attachments:ARRAY<STRUCT<name:STRING,contentType:STRING,path:STRING>>,stdout:ARRAY<STRING>,stderr:ARRAY<STRING>>>>>>>,suites:ARRAY<STRING>>'),
                    'depth',
                    entry.depth + 1,
                    'path',
                    concat(
                      entry.path,
                      filter(array(from_json(child_json, 'STRUCT<title:STRING,file:STRING,line:INT,column:INT,specs:ARRAY<STRUCT<title:STRING,id:STRING,file:STRING,line:INT,column:INT,ok:BOOLEAN,tags:ARRAY<STRING>,tests:ARRAY<STRUCT<timeout:INT,expectedStatus:STRING,projectId:STRING,projectName:STRING,status:STRING,results:ARRAY<STRUCT<workerIndex:INT,parallelIndex:INT,status:STRING,duration:INT,retry:INT,startTime:STRING,errors:ARRAY<STRUCT<message:STRING,stack:STRING>>,attachments:ARRAY<STRUCT<name:STRING,contentType:STRING,path:STRING>>,stdout:ARRAY<STRING>,stderr:ARRAY<STRING>>>>>>>,suites:ARRAY<STRING>>').title), y -> y IS NOT NULL)
                    )
                  )
                )
            )
          ),
          'collected',
          concat(state.collected, state.pending)
        )
    ) AS suite_state
  FROM rooted
),
suite_rows AS (
  SELECT
    sa.file_path,
    sa.test_type,
    sa.repository,
    sa.deploy_group,
    sa.service,
    sa.ci_build_id,
    sa.run_date,
    sa.year,
    sa.month,
    sa.day,
    sa.parsed,
    suite_entry.suite AS suite,
    suite_entry.depth AS suite_depth,
    suite_entry.path AS suite_path
  FROM suite_accum sa
  LATERAL VIEW explode(sa.suite_state.collected) suite_table AS suite_entry
  WHERE suite_entry.suite IS NOT NULL
),
spec_level AS (
  SELECT
    sr.file_path,
    sr.test_type,
    sr.repository,
    sr.deploy_group,
    sr.service,
    sr.ci_build_id,
    sr.run_date,
    sr.year,
    sr.month,
    sr.day,
    sr.parsed,
    sr.suite,
    sr.suite_depth,
    sr.suite_path,
    spec,
    spec_index
  FROM suite_rows sr
  LATERAL VIEW posexplode_outer(sr.suite.specs) spec_table AS spec_index, spec
  WHERE spec IS NOT NULL
),
test_level AS (
  SELECT
    sl.file_path,
    sl.test_type,
    sl.repository,
    sl.deploy_group,
    sl.service,
    sl.ci_build_id,
    sl.run_date,
    sl.year,
    sl.month,
    sl.day,
    sl.parsed,
    sl.suite,
    sl.suite_depth,
    sl.suite_path,
    sl.spec,
    sl.spec_index,
    test,
    test_index
  FROM spec_level sl
  LATERAL VIEW posexplode_outer(sl.spec.tests) test_table AS test_index, test
  WHERE test IS NOT NULL
),
result_level AS (
  SELECT
    tl.file_path,
    tl.test_type,
    tl.repository,
    tl.deploy_group,
    tl.service,
    tl.ci_build_id,
    tl.run_date,
    tl.year,
    tl.month,
    tl.day,
    tl.parsed,
    tl.suite,
    tl.suite_depth,
    tl.suite_path,
    tl.spec,
    tl.spec_index,
    tl.test,
    tl.test_index,
    result,
    result_index
  FROM test_level tl
  LATERAL VIEW posexplode_outer(tl.test.results) result_table AS result_index, result
  WHERE result IS NOT NULL
)
SELECT
  -- ids (0)
  rl.ci_build_id AS id_ci_build,
  rl.spec.id AS id_spec,
  rl.test.projectId AS id_test_project,
  concat_ws(
    '|',
    rl.ci_build_id,
    rl.spec.id,
    rl.test.projectId,
    cast(rl.result.retry AS string)
  ) AS id_unique_test_result,
  -- non-ids (1)
  rl.parsed.config.metadata.gitCommit.hash AS git_commit_hash,
  rl.parsed.config.metadata.gitCommit.shortHash AS git_commit_short,
  -- general properties (2)
  rl.file_path,
  rl.test_type,
  rl.repository,
  rl.deploy_group,
  rl.service,
  rl.parsed.config.version AS playwright_version,
  rl.parsed.config.workers AS config_max_workers,
  rl.parsed.config.rootDir AS config_root_dir,
  rl.parsed.config.metadata.actualWorkers AS actual_workers,
  rl.parsed.config.metadata.gitCommit.branch AS git_branch,
  rl.parsed.config.metadata.gitCommit.subject AS git_commit_subject,
  rl.parsed.config.metadata.gitCommit.author.name AS commit_author_name,
  rl.parsed.config.metadata.gitCommit.author.email AS commit_author_email,
  rl.suite.title AS suite_title,
  rl.suite.file AS suite_file,
  rl.suite.line AS suite_line,
  rl.suite.column AS suite_column,
  rl.spec.title AS spec_title,
  rl.spec.file AS spec_file,
  rl.spec.line AS spec_line,
  rl.spec.column AS spec_column,
  rl.spec.tags AS spec_tags,
  rl.test.timeout AS test_timeout,
  rl.test.expectedStatus AS test_expected_status,
  rl.test.projectName AS test_project_name,
  rl.test.status AS test_overall_status,
  rl.result.workerIndex AS result_worker_index,
  rl.result.parallelIndex AS result_parallel_index,
  rl.result.status AS result_status,
  rl.result.retry AS result_retry_attempt,
  rl.result.startTime AS result_start_time,
  rl.parsed.stats.startTime AS run_start_time,
  rl.result.errors AS result_errors,
  rl.result.attachments AS result_attachments,
  rl.result.stdout AS result_stdout,
  rl.result.stderr AS result_stderr,
  CASE
    WHEN size(rl.result.errors) > 0 THEN rl.result.errors[0].message
    ELSE NULL
  END AS first_error_message,
  CASE
    WHEN size(rl.result.errors) > 0 THEN rl.result.errors[0].stack
    ELSE NULL
  END AS first_error_stack,
  -- metrics/booleans (3)
  rl.parsed.stats.expected AS run_total_expected,
  rl.parsed.stats.unexpected AS run_total_unexpected,
  rl.parsed.stats.flaky AS run_total_flaky,
  rl.parsed.stats.skipped AS run_total_skipped,
  rl.parsed.stats.duration AS run_total_duration_ms,
  rl.result.duration AS result_duration_ms,
  rl.spec.ok AS is_spec_ok,
  CASE
    WHEN rl.result.retry > 0 AND rl.result.status = 'passed' THEN TRUE
    ELSE FALSE
  END AS is_flaky_test,
  CASE
    WHEN rl.result.status = 'passed' THEN TRUE
    ELSE FALSE
  END AS is_passed,
  CASE
    WHEN rl.result.status = 'failed' THEN TRUE
    ELSE FALSE
  END AS is_failed,
  CASE
    WHEN rl.result.status = 'skipped' THEN TRUE
    ELSE FALSE
  END AS is_skipped,
  CASE
    WHEN rl.result.status = 'timedOut' THEN TRUE
    ELSE FALSE
  END AS is_timeout,
  rl.result.retry + 1 AS total_attempts_for_this_result,
  size(rl.result.errors) AS error_count,
  size(rl.result.attachments) AS attachment_count,
  size(rl.result.stdout) AS stdout_line_count,
  size(rl.result.stderr) AS stderr_line_count,
  -- dates/timestamps (4)
  rl.run_date AS dt_run,
  rl.parsed.config.metadata.gitCommit.author.time AS ts_commit_author,
  to_timestamp(rl.result.startTime) AS ts_result_start,
  to_timestamp(rl.parsed.stats.startTime) AS ts_run_start,
  date(to_timestamp(rl.parsed.stats.startTime)) AS dt_run_parsed,
  -- partitions (5)
  rl.year,
  rl.month,
  rl.day,
  year(to_timestamp(rl.parsed.stats.startTime)) AS run_year,
  month(to_timestamp(rl.parsed.stats.startTime)) AS run_month,
  day(to_timestamp(rl.parsed.stats.startTime)) AS run_day,
  hour(to_timestamp(rl.parsed.stats.startTime)) AS run_hour
FROM result_level rl;
