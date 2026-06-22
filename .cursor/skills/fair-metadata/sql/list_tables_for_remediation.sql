-- Batch triage: FQNs below tier 2 on the most recent run.
-- fairness_classification = filter/sort by human-readable class only.
-- fairness_assessment (join on ts_assessed) = checks_result_json required to remediate.
-- Do not use classification without checks_result_json.
-- Run via trino/SKILL.md (fair-metadata).

SELECT
    fc.database_name,
    fc.table_name,
    fc.classification,
    fa.tier_achieved,
    fa.checks_result_json,
    fa.ts_assessed
FROM datalake_fairness_assessment.fairness_classification AS fc
INNER JOIN datalake_fairness_assessment.fairness_assessment AS fa
    ON fc.database_name = fa.database_name
    AND fc.table_name = fa.table_name
    AND fc.ts_assessed = fa.ts_assessed
WHERE fa.tier_achieved < 2
-- Scope (see reference/scoping.md): by domain, by owner, and/or repo FQN list.
-- By owner — join tables_documentation on owner = '<email>' (latest partition), then fa join as in scoping.md.
-- By domain — pick one or combine with repo FQN list from dags/{domain}/:
-- (1) Join catalog domain (exact allowlist string):
-- INNER JOIN (
--     SELECT DISTINCT database_name, table_name
--     FROM datalake_documentation_metrics_clean.tables_documentation
--     WHERE domain = 'Data Ops & Governance'  -- example; use fairness_metadata.mdc allowlist
--       AND DATE(CAST(year AS VARCHAR) || '-' || LPAD(CAST(month AS VARCHAR), 2, '0') || '-' || LPAD(CAST(day AS VARCHAR), 2, '0')) = (SELECT MAX(DATE(CAST(year AS VARCHAR) || '-' || LPAD(CAST(month AS VARCHAR), 2, '0') || '-' || LPAD(CAST(day AS VARCHAR), 2, '0'))) FROM datalake_documentation_metrics_clean.tables_documentation)
-- ) td ON fa.database_name = td.database_name AND fa.table_name = td.table_name
-- (2) Or restrict to FQNs extracted from dags/{domain}/**/metadata/*/*.yml:
-- AND (fa.database_name, fa.table_name) IN (('datalake_foo_clean', 'bar'), ...)
ORDER BY fa.tier_achieved ASC, fc.database_name, fc.table_name
LIMIT 100
