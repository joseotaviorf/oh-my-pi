-- Most recent enrich_fairness_assessment RUN for one table (primary remediation input).
-- One row per FQN per run (partition year/month/day); ORDER BY ts_assessed DESC = latest execution.
-- Run via Trino (@tars). Zero rows → table never assessed; use pointual checks instead.
-- Point FQN lookup: ORDER BY ts_assessed DESC LIMIT 1 returns the latest run across
-- partitions; a fixed day window would miss tables assessed less frequently.

SELECT
    database_name,
    table_name,
    tier_achieved,
    is_active_employee,
    has_data_contract,
    table_description_is_substantive,
    columns_description_is_substantive,
    ts_assessed,
    checks_result_json,
    year,
    month,
    day
FROM datalake_fairness_assessment.fairness_assessment
WHERE database_name = '{database_name}'
  AND table_name = '{table_name}'
ORDER BY ts_assessed DESC
LIMIT 1
