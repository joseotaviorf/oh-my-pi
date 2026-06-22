-- Latest assessment row for one FQN (primary remediation input from enrich_fairness_assessment).
-- Grain: one row per (database_name, table_name, year, month, day).
-- Run via trino/SKILL.md (fair-metadata; optional).
-- Zero rows → table never assessed; use pointual checks instead.
-- Latest row = highest ts_assessed for this FQN across all partitions (no lake-wide or
-- sliding partition window — those miss tables whose last run predates the global newest partition).

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
